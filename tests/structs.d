import std.json;

import tests.types;
import jsonizer.fromjson;
import jsonizer.tojson;

// assert that an object can be serialized to JSON and then reconstructed
void runTest(T, Params ...)(Params params) {
  T obj = T(params);
  // check JSONValue serialization
  assert(obj.toJSON.fromJSON!T == obj);
  // check JSON string serialization
  assert(obj.toJSONString.fromJSONString!T == obj);
}

// helper to make an empty instance of an array type T
template emptyArray(T) {
  enum emptyArray = cast(T) [];
}

auto staticArray(T, Params ...)(Params params) {
  return cast(T[Params.length]) [params];
}

unittest {
  runTest!PrimitiveStruct(1, 2UL, true, 0.4f, 0.8, "wat?"); // general case
  runTest!PrimitiveStruct(0, 40, false, 0.4f, 22.8, "");    // empty string
  runTest!PrimitiveStruct(0, 40, false, 0.4f, 22.8, null);  // null string
  // NaN and Inf are currently not handled by std.json
  //runTest!PrimitiveStruct(0, 40, false, float.nan, 22.8, null);
}

unittest {
  runTest!PrivateFieldsStruct(1, 2UL, true, 0.4f, 0.8, "wat?");
}

unittest {
  runTest!PropertyStruct(4, false, -2.7f, "asdf");
}

unittest {
  runTest!ArrayStruct([1, 2, 3], ["a", "b", "c"]);                // populated arrays
  runTest!ArrayStruct([1, 2, 3], ["a", null, "c"]);               // null in array
  runTest!ArrayStruct(emptyArray!(int[]), emptyArray!(string[])); // empty arrays
  runTest!ArrayStruct(null, null);                                // null arrays
}

unittest {
  runTest!NestedArrayStruct([[1, 2], [3, 4]], [["a", "b"], ["c", "d"]]);    // nested arrays
  runTest!NestedArrayStruct([null, [3, 4]], cast(string[][]) [null]);       // null entries
  runTest!NestedArrayStruct(emptyArray!(int[][]), emptyArray!(string[][])); // empty arrays
  runTest!NestedArrayStruct(null, null);                                    // null arrays
}

unittest {
  runTest!StaticArrayStruct(staticArray!int(1, 2, 3), staticArray!string("a", "b"));
}

unittest {
  runTest!NestedStruct(5, "ra", 4.2, [2, 3]);
}

unittest {
  auto json = q{{ "inner": { "i": 1 } }};
  auto nested = json.fromJSONString!Nested2;
  assert(nested.inner.i == 1);
}

unittest {
  runTest!AliasedTypeStruct([2, 3]);
}

unittest {
  runTest!CustomCtorStruct(1, 4.2f);
}

unittest {
  runTest!(GenericStruct!int)(5);
  runTest!(GenericStruct!string)("s");
  runTest!(GenericStruct!PrimitiveStruct)(PrimitiveStruct(1, 2UL, true, 0.4f, 0.8, "wat?"));
}

unittest {
  auto jstr = "5";
  assert(jstr.fromJSONString!IntStruct == IntStruct(5));
}

unittest {
  assert(`{"i": 5, "j": 7}`.fromJSONString!JSONValueStruct ==
         JSONValueStruct(5, JSONValue(7)));
  assert(`{"i": 5, "j": "hi"}`.fromJSONString!JSONValueStruct ==
         JSONValueStruct(5, JSONValue("hi")));
}
