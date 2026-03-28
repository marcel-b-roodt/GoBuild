using Xunit;

namespace GoBuild.Tests.Mesh;

/// <summary>
/// Tests for primitive shape generators.
/// Stubs — flesh out as each generator is implemented.
/// </summary>
public class ShapeGeneratorTests
{
    // ── Cube ────────────────────────────────────────────────────────────

    [Fact]
    public void Cube_Placeholder_AlwaysPasses()
    {
        // TODO: Assert CubeGenerator.Generate(1,1,1,0).Faces.Count == 6
        Assert.True(true);
    }

    // ── Plane ───────────────────────────────────────────────────────────

    [Fact]
    public void Plane_Placeholder_AlwaysPasses()
    {
        // TODO: Assert PlaneGenerator.Generate(1,1,1,1).Faces.Count == 1
        Assert.True(true);
    }

    // ── Cylinder ────────────────────────────────────────────────────────

    [Fact]
    public void Cylinder_Placeholder_AlwaysPasses()
    {
        Assert.True(true);
    }
}


