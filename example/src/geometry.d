module geometry;

import jsonizer;

struct Vector {
  mixin JsonizeMe;
  @jsonize {
    int x, y;
  }
}

struct Rect {
  mixin JsonizeMe;
  @jsonize {
    int x, y, w, h;
  }
}
