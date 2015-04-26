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

unittest {
  auto orig = new DoubleNested;
  orig.inner = orig.new Inner;
  orig.inner.inner = orig.inner.new Inner;
  orig.inner.inner.i = 5;

  auto json = orig.toJSON;
  auto result = json.fromJSON!DoubleNested;

  assert(result.inner !is null, "failed to construct nested class");
  assert(result.inner.inner !is null, "failed to construct doubly nested class");
  assert(result.inner.inner.i == orig.inner.inner.i, "failed to serialize doubly nested class field");
}

unittest {
  auto orig = new NestedClassArray;
  orig.inners = [ orig.new Inner(), orig.new Inner() ];

  auto json = orig.toJSON;
  auto result = json.fromJSON!NestedClassArray;

  assert(result.inners !is null, "failed to construct nested class array");
  assert(result.inners.length == 2, "incorrect length for inner class array");
  assert(result.inners[0].i == orig.inners[0].i, "incorrect inner class array value");
  assert(result.inners[1].i == orig.inners[1].i, "incorrect inner class array value");
}
