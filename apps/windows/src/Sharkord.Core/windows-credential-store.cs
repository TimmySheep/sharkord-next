using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace Sharkord.Core;

public static class WindowsCredentialStore
{
    public static string Target(string server) => $"Cove/login/{LastChannelPreference.SettingKey(server).Split('.').Last()}";

    public static void Save(string server, string identity, string password)
    {
        var bytes = Encoding.Unicode.GetBytes(password);
        if (bytes.Length > 2560) { throw new ArgumentOutOfRangeException(nameof(password)); }
        var pinned = GCHandle.Alloc(bytes, GCHandleType.Pinned);
        try
        {
            var credential = new Credential
            {
                Type = 1, TargetName = Target(server), UserName = identity,
                BlobSize = (uint)bytes.Length, Blob = pinned.AddrOfPinnedObject(), Persist = 2
            };
            if (!CredWrite(ref credential, 0)) { throw new Win32Exception(Marshal.GetLastWin32Error()); }
        }
        finally { pinned.Free(); CryptographicOperations.ZeroMemory(bytes); }
    }

    public static SavedCredential? Read(string server)
    {
        if (!CredRead(Target(server), 1, 0, out var pointer))
        {
            var error = Marshal.GetLastWin32Error();
            if (error == 1168) { return null; }
            throw new Win32Exception(error);
        }
        try
        {
            var credential = Marshal.PtrToStructure<Credential>(pointer);
            if (credential.BlobSize > 2560 || credential.BlobSize % 2 != 0) { return null; }
            var bytes = new byte[(int)credential.BlobSize];
            try
            {
                Marshal.Copy(credential.Blob, bytes, 0, bytes.Length);
                return new SavedCredential(credential.UserName ?? "", Encoding.Unicode.GetString(bytes));
            }
            finally { CryptographicOperations.ZeroMemory(bytes); }
        }
        finally { CredFree(pointer); }
    }

    public static void Remove(string server)
    {
        if (!CredDelete(Target(server), 1, 0) && Marshal.GetLastWin32Error() != 1168)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string? Comment;
        public long LastWritten;
        public uint BlobSize;
        public IntPtr Blob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias;
        public string? UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredWrite(ref Credential credential, uint flags);
    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);
    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredDelete(string target, uint type, uint flags);
    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr credential);
}

public sealed class SavedCredential(string identity, string password)
{
    public string Identity { get; } = identity;
    public string Password { get; } = password;
}
