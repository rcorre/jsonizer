module entity;

import geometry;
import component;
import jsonizer;

class Entity {
  mixin JsonizeMe;

  @jsonize {
    Vector position;
    Component[] components;
  }
}
