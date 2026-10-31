using System.Text.Json.Nodes;
using Sharkord.Core;
using Xunit;

namespace Sharkord.Core.Tests;

public class MessageMetadataTests
{
    [Fact]
    public void MetadataKeepsMediaAndCardsAndRejectsUnsafeOrDuplicateDestinations()
    {
        var message = JsonNode.Parse("""
            {"metadata":[null,
              {"kind":"open_graph","url":"https://example.com/post","title":"A <title>","images":["file:///private.png","https://example.com/image.png"]},
              {"kind":"open_graph","url":"https://example.com/post#fragment","title":"duplicate"},
              {"kind":"media","url":"https://example.com/clip.mp4","mediaType":"video"},
              {"kind":"open_graph","url":"javascript:alert(1)","title":"unsafe"}]}
            """)!.DeserializeObject<SharkordMessage>()!;
        var previews = MessageMetadata.Previews(message);
        Assert.Equal(2, previews.Count);
        Assert.Equal("A <title>", previews[0].Title);
        Assert.Equal("https://example.com/image.png", previews[0].Image?.AbsoluteUri);
        Assert.Equal("video", previews[1].MediaType);
    }
}
