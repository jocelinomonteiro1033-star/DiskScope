using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;

namespace DiskScope.Core
{
    public sealed class FileRecord
    {
        public string Name { get; set; }
        public string FullPath { get; set; }
        public long Size { get; set; }
        public DateTime CreationTime { get; set; }
        public DateTime LastWriteTime { get; set; }
        public DateTime LastAccessTime { get; set; }
        public string Extension { get; set; }
    }

    public sealed class DuplicateGroup
    {
        public string Hash { get; set; }
        public long FileSize { get; set; }
        public List<FileRecord> Files { get; set; }
        public long ReclaimableSize => FileSize * Math.Max(0, (Files?.Count ?? 0) - 1);
    }

    public sealed class DuplicateJob
    {
        internal readonly CancellationTokenSource Cancellation = new CancellationTokenSource();
        private long _hashedFiles;
        private long _candidateFiles;
        private string _currentPath = string.Empty;

        public Task<List<DuplicateGroup>> Task { get; internal set; }
        public long HashedFiles => Interlocked.Read(ref _hashedFiles);
        public long CandidateFiles => Interlocked.Read(ref _candidateFiles);
        public string CurrentPath => Volatile.Read(ref _currentPath);

        internal void SetCandidateFiles(long value) => Interlocked.Exchange(ref _candidateFiles, value);
        internal void FileHashed() => Interlocked.Increment(ref _hashedFiles);
        internal void SetCurrentPath(string path) => Volatile.Write(ref _currentPath, path ?? string.Empty);
        public void Cancel() => Cancellation.Cancel();
    }

    public sealed class ScanNode
    {
        public string Name { get; set; }
        public string FullPath { get; set; }
        public long DirectSize { get; set; }
        public long TotalSize { get; set; }
        public long FileCount { get; set; }
        public long DirectoryCount { get; set; }
        public bool IsReparsePoint { get; set; }
        public bool IsInaccessible { get; set; }
        public string Error { get; set; }
        public List<ScanNode> Directories { get; } = new List<ScanNode>();
        public List<FileRecord> Files { get; } = new List<FileRecord>();
    }

    public sealed class ScanJob
    {
        internal readonly CancellationTokenSource Cancellation = new CancellationTokenSource();
        private long _filesScanned;
        private long _directoriesScanned;
        private string _currentPath = string.Empty;

        public Task<ScanNode> Task { get; internal set; }
        public long FilesScanned => Interlocked.Read(ref _filesScanned);
        public long DirectoriesScanned => Interlocked.Read(ref _directoriesScanned);
        public string CurrentPath => Volatile.Read(ref _currentPath);

        internal void FileFound() => Interlocked.Increment(ref _filesScanned);
        internal void DirectoryFound() => Interlocked.Increment(ref _directoriesScanned);
        internal void SetCurrentPath(string path) => Volatile.Write(ref _currentPath, path ?? string.Empty);
        public void Cancel() => Cancellation.Cancel();
    }

    public static class Scanner
    {
        public static ScanJob Start(string rootPath)
        {
            if (string.IsNullOrWhiteSpace(rootPath))
                throw new ArgumentException("Selecione uma pasta.", nameof(rootPath));

            string fullPath = Path.GetFullPath(rootPath);
            if (!Directory.Exists(fullPath))
                throw new DirectoryNotFoundException(fullPath);

            var job = new ScanJob();
            job.Task = Task.Run(() => ScanDirectory(fullPath, job, job.Cancellation.Token), job.Cancellation.Token);
            return job;
        }

        private static ScanNode ScanDirectory(string path, ScanJob job, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            job.DirectoryFound();
            job.SetCurrentPath(path);

            var info = new DirectoryInfo(path);
            var node = new ScanNode
            {
                Name = string.IsNullOrEmpty(info.Name) ? info.FullName : info.Name,
                FullPath = info.FullName
            };

            try
            {
                if ((info.Attributes & FileAttributes.ReparsePoint) != 0)
                {
                    node.IsReparsePoint = true;
                    return node;
                }

                foreach (string filePath in Directory.EnumerateFiles(path))
                {
                    token.ThrowIfCancellationRequested();
                    try
                    {
                        var file = new FileInfo(filePath);
                        node.Files.Add(new FileRecord
                        {
                            Name = file.Name,
                            FullPath = file.FullName,
                            Size = file.Length,
                            CreationTime = file.CreationTime,
                            LastWriteTime = file.LastWriteTime,
                            LastAccessTime = file.LastAccessTime,
                            Extension = file.Extension ?? string.Empty
                        });
                        node.DirectSize += file.Length;
                        job.FileFound();
                    }
                    catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException || ex is System.Security.SecurityException)
                    {
                        // A file can disappear or become inaccessible during a live scan.
                    }
                }

                foreach (string directoryPath in Directory.EnumerateDirectories(path))
                {
                    token.ThrowIfCancellationRequested();
                    ScanNode child;
                    try
                    {
                        child = ScanDirectory(directoryPath, job, token);
                    }
                    catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException || ex is System.Security.SecurityException)
                    {
                        child = new ScanNode
                        {
                            Name = Path.GetFileName(directoryPath),
                            FullPath = directoryPath,
                            IsInaccessible = true,
                            Error = ex.Message
                        };
                    }
                    node.Directories.Add(child);
                }
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException || ex is System.Security.SecurityException)
            {
                node.IsInaccessible = true;
                node.Error = ex.Message;
            }

            node.TotalSize = node.DirectSize + node.Directories.Sum(child => child.TotalSize);
            node.FileCount = node.Files.Count + node.Directories.Sum(child => child.FileCount);
            node.DirectoryCount = node.Directories.Count + node.Directories.Sum(child => child.DirectoryCount);
            node.Directories.Sort((left, right) => right.TotalSize.CompareTo(left.TotalSize));
            node.Files.Sort((left, right) => right.Size.CompareTo(left.Size));
            return node;
        }
    }

    public static class DuplicateFinder
    {
        public static DuplicateJob Start(ScanNode root)
        {
            if (root == null) throw new ArgumentNullException(nameof(root));
            var job = new DuplicateJob();
            job.Task = Task.Run(() => Find(root, job, job.Cancellation.Token), job.Cancellation.Token);
            return job;
        }

        private static List<DuplicateGroup> Find(ScanNode root, DuplicateJob job, CancellationToken token)
        {
            var allFiles = EnumerateFiles(root).ToList();
            var candidates = allFiles
                .Where(file => file.Size > 0)
                .GroupBy(file => file.Size)
                .Where(group => group.Count() > 1)
                .SelectMany(group => group)
                .ToList();

            job.SetCandidateFiles(candidates.Count);
            var matches = new Dictionary<string, List<FileRecord>>(StringComparer.Ordinal);
            using (SHA256 sha = SHA256.Create())
            {
                foreach (FileRecord file in candidates)
                {
                    token.ThrowIfCancellationRequested();
                    job.SetCurrentPath(file.FullPath);
                    try
                    {
                        byte[] digest;
                        using (var stream = new FileStream(file.FullPath, FileMode.Open, FileAccess.Read,
                            FileShare.ReadWrite | FileShare.Delete, 1024 * 1024, FileOptions.SequentialScan))
                        {
                            digest = sha.ComputeHash(stream);
                        }
                        string hash = file.Size.ToString() + ":" + BitConverter.ToString(digest).Replace("-", string.Empty);
                        if (!matches.TryGetValue(hash, out List<FileRecord> group))
                        {
                            group = new List<FileRecord>();
                            matches.Add(hash, group);
                        }
                        group.Add(file);
                    }
                    catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException || ex is System.Security.SecurityException)
                    {
                        // Arquivos alterados, bloqueados ou removidos durante a análise são ignorados.
                    }
                    finally
                    {
                        job.FileHashed();
                    }
                }
            }

            return matches
                .Where(pair => pair.Value.Count > 1)
                .Select(pair => new DuplicateGroup
                {
                    Hash = pair.Key.Substring(pair.Key.IndexOf(':') + 1),
                    FileSize = pair.Value[0].Size,
                    Files = pair.Value.OrderByDescending(file => file.LastWriteTime).ToList()
                })
                .OrderByDescending(group => group.ReclaimableSize)
                .ToList();
        }

        private static IEnumerable<FileRecord> EnumerateFiles(ScanNode root)
        {
            var pending = new Stack<ScanNode>();
            pending.Push(root);
            while (pending.Count > 0)
            {
                ScanNode node = pending.Pop();
                foreach (FileRecord file in node.Files) yield return file;
                foreach (ScanNode child in node.Directories) pending.Push(child);
            }
        }
    }
}
