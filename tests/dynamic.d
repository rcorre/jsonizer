module tests.dynamic;

import tests.types;
import jsonizer.fromjson;
import jsonizer.tojson;

enum jsonString = q{
  [
    {
      "class": "tests.types.ParentClass",
      "parentVal": 3
    },
    {
      "class": "tests.types.ChildA",
      "parentVal": 2,
      "a": 5
    },
    {
      "class": "tests.types.ChildB",
      "parentVal": 4,
      "b": [5, 4, 3]
    }
  ]
};

unittest {
  auto objects = jsonString.fromJSONString!(ParentClass[]);

  assert(typeid(objects[0]) == typeid(ParentClass));
  assert(typeid(objects[1]) == typeid(ChildA));
  assert(typeid(objects[2]) == typeid(ChildB));
  auto parent = objects[0];
  auto a = cast(ChildA) objects[1];
  auto b = cast(ChildB) objects[2];

  assert(parent.parentVal == 3);

  assert(a.parentVal == 2);
  assert(a.a == 5);

  assert(b.parentVal == 4);
  assert(b.b == [5, 4, 3]);
}
