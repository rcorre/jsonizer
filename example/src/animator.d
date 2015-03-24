module animator;

import std.string;
import geometry;
import component;
import jsonizer.jsonize : jsonize, JsonizeMe;

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

  override string stringify() {
    enum fmt = 
      `Animator Component:
      frameTime : %f
      repeat    : %s`;
    return fmt.format(frameTime, repeat);
  }
}
