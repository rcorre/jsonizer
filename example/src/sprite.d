module sprite;

import std.string;
import geometry;
import component;
import jsonizer;

class Sprite : Component {
  mixin JsonizeMe;

  @jsonize {
    string textureName;
    int depth;
    Rect textureRegion;
  }

  override string stringify() {
    enum fmt = 
      `Sprite Component:
      textureName   : %s
      textureRegion : [%d, %d, %d, %d]
      depth         : %d`;
    return fmt.format(
        textureName,
        textureRegion.x, textureRegion.y, textureRegion.w, textureRegion.h,
        depth);
  }
}
