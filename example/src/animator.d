module animator;

import geometry;
import component;
import jsonizer;

class Animator : Component {
  mixin JsonizeMe;

  enum Repeat {
    no,
    loop,
    reverse
  }

  @jsonize {
    float frameTime;
    Repeat repeat;
  }
}
