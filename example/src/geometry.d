module geometry;

// try importing the entire jsonizer package
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
