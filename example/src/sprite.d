module sprite;

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
}
