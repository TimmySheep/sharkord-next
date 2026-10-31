using System.Text;
using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public class EventSoundTests
{
    [Fact]
    public void EverySoundIsABoundedMonoPcmWaveWithADistinctSignal()
    {
        var signatures = new HashSet<string>();
        foreach (var name in EventSounds.Names)
        {
            var wave = EventSounds.Wave(name);
            Assert.Equal("RIFF", Encoding.ASCII.GetString(wave, 0, 4));
            Assert.Equal("WAVE", Encoding.ASCII.GetString(wave, 8, 4));
            Assert.Equal(wave.Length - 8, BitConverter.ToInt32(wave, 4));
            Assert.Equal(1, BitConverter.ToInt16(wave, 22));
            Assert.Equal(16, BitConverter.ToInt16(wave, 34));
            Assert.InRange(wave.Length, 1000, 50000);
            Assert.Contains(wave.Skip(44), sample => sample != 0);
            Assert.True(signatures.Add(Convert.ToBase64String(System.Security.Cryptography.SHA256.HashData(wave))));
        }
        Assert.Equal(17, EventSounds.Names.Count);
    }
}
