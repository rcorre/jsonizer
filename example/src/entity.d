module entity;

import geometry;
import component;
import jsonizer.all;

class Entity {
  mixin JsonizeMe;

  @jsonize {
    Vector position;
    Component[] components;
  }
}
