module entity;

import geometry;
import component;
import jsonizer.jsonize : jsonize, JsonizeMe;

class Entity {
  mixin JsonizeMe;

  @jsonize {
    Vector position;
    Component[] components;
  }
}
