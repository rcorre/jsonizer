module tests.classes;

import tests.types;
import jsonizer;

// assert that an object can be serialized to JSON and then reconstructed
void runTest(T)(T obj) {
  // check JSONValue serialization
  assert(obj.toJSON.fromJSON!T == obj);
  // check JSON string serialization
  assert(obj.toJSONString.fromJSONString!T == obj);
}

unittest {
  auto obj = new OuterClass;
  obj.outerVal = 5;
  obj.inner = obj.new InnerClass;
  obj.inner.innerVal = 10;
  runTest(obj);
}

unittest {
  auto obj = new OuterClassCtor;
  obj.outerVal = 5;
  obj.inner = obj.new InnerClass(10);
  runTest(obj);
}

unittest {
  assert("null".fromJSONString!SimpleClass is null);
}
