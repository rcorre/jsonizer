import std.math : approxEqual;
import geometry;
import entity;
import component;
import sprite;
import animator;
import jsonizer;

private enum fileName = "entities.json";

void main() {
  auto entities = fileName.readJSON!(Entity[string]);
  auto player = entities["player"];
  assert(player.position == Vector(5, 40));
  foreach(component ; player.components) {
    if (auto animator = cast(Animator) component) {
      assert(animator.frameTime.approxEqual(0.033f));
      assert(animator.repeat == Animator.Repeat.loop);
    }
    else if (auto sprite = cast(Sprite) component) {
      assert(sprite.textureName == "person");
      assert(sprite.depth == 1);
      assert(sprite.textureRegion == Rect(0, 0, 32, 32));
    }
  }
}
