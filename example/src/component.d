module component;

import jsonizer;

abstract class Component {
  mixin JsonizeMe;

  // create a string representation of this component, just to show it was populated
  string stringify();
}
