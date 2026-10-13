using System.ComponentModel;
using System.Runtime.InteropServices;
using Sharkord.Core;

namespace Sharkord.App;

internal sealed class GlobalPushToTalkHook : IDisposable
{
    private const int LowLevelKeyboardHook = 13;
    private const int KeyDownMessage = 0x0100;
    private const int KeyUpMessage = 0x0101;
    private const int SystemKeyDownMessage = 0x0104;
    private const int SystemKeyUpMessage = 0x0105;
    private const uint F13VirtualKey = 0x7C;

    private readonly HookProcedure _procedure;
    private IntPtr _hook;

    public event Action<bool>? KeyStateChanged;

    public GlobalPushToTalkHook()
    {
        _procedure = OnKeyboardEvent;
    }

    public void Start()
    {
        if (_hook != IntPtr.Zero)
        {
            return;
        }

        _hook = SetWindowsHookEx(LowLevelKeyboardHook, _procedure, GetModuleHandle(null), 0);
        if (_hook == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }

    public void Dispose()
    {
        if (_hook == IntPtr.Zero)
        {
            return;
        }

        UnhookWindowsHookEx(_hook);
        _hook = IntPtr.Zero;
    }

    private IntPtr OnKeyboardEvent(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0)
        {
            var messageId = message.ToInt32();
            if (messageId is KeyDownMessage or SystemKeyDownMessage or KeyUpMessage or SystemKeyUpMessage)
            {
                var key = Marshal.PtrToStructure<KeyboardHookData>(data);
                if (key.VirtualKey == F13VirtualKey)
                {
                    try
                    {
                        KeyStateChanged?.Invoke(messageId is KeyDownMessage or SystemKeyDownMessage);
                    }
                    catch (Exception exception)
                    {
                        ClientLogStore.Shared.RecordError("voice.push_to_talk.hook_callback_failed", exception);
                    }
                }
            }
        }

        return CallNextHookEx(IntPtr.Zero, code, message, data);
    }

    private delegate IntPtr HookProcedure(int code, IntPtr message, IntPtr data);

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardHookData
    {
        public uint VirtualKey;
        public uint ScanCode;
        public uint Flags;
        public uint Time;
        public UIntPtr ExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(
        int hookId,
        HookProcedure procedure,
        IntPtr moduleHandle,
        uint threadId
    );

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string? moduleName);
}
