using System.Text;

namespace Sharkord.Core;

public static class EventSounds
{
    public static IReadOnlyList<string> Names { get; } = [
        "message_received", "message_sent", "server_disconnected",
        "own_user_joined_voice_channel", "own_user_left_voice_channel",
        "own_user_muted_mic", "own_user_unmuted_mic", "own_user_muted_sound", "own_user_unmuted_sound",
        "own_user_started_webcam", "own_user_stopped_webcam", "own_user_started_screenshare", "own_user_stopped_screenshare",
        "remote_user_joined_voice_channel", "remote_user_left_voice_channel", "remote_user_started_screenshare", "remote_user_stopped_screenshare"
    ];

    public static byte[] Wave(string name)
    {
        var index = Names.ToList().IndexOf(name);
        ArgumentOutOfRangeException.ThrowIfNegative(index);
        const int sampleRate = 24000;
        var seconds = index < 2 ? .06 : .2;
        var samples = (int)(sampleRate * seconds);
        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream, Encoding.ASCII, leaveOpen: true);
        writer.Write("RIFF"u8); writer.Write(36 + samples * 2); writer.Write("WAVEfmt "u8);
        writer.Write(16); writer.Write((short)1); writer.Write((short)1); writer.Write(sampleRate);
        writer.Write(sampleRate * 2); writer.Write((short)2); writer.Write((short)16);
        writer.Write("data"u8); writer.Write(samples * 2);
        var frequency = 350 + index * 43;
        for (var sample = 0; sample < samples; sample++)
        {
            var elapsed = sample / (double)sampleRate;
            var envelope = Math.Min(1, elapsed / .005) * Math.Exp(-elapsed * 28);
            writer.Write((short)(Math.Sin(2 * Math.PI * frequency * elapsed) * envelope * 3500));
        }
        return stream.ToArray();
    }
}
