import tests.types;
import jsonizer.fromjson;
import jsonizer.tojson;

// assert that an object is the same after serializing and deserializing.
void runTest(T, Params ...)(Params params) {
  T obj = T(params);
  assert(obj.toJSON.fromJSON!T == obj);
  assert(obj.toJSONString.fromJSONString!T == obj);
}

unittest {
  runTest!PrimitiveStruct(1, 2UL, true, 0.4f, 0.8, "wat?"); // general case
  runTest!PrimitiveStruct(0, 40, false, 0.4f, 22.8, "");    // empty string
  runTest!PrimitiveStruct(0, 40, false, 0.4f, 22.8, null);  // null string
  //runTest!PrimitiveStruct(0, 40, false, float.nan, 22.8, null);  // null string
}

unittest {
  runTest!PrivateFieldsStruct(1, 2UL, true, 0.4f, 0.8, "wat?");
}

unittest {
  runTest!StructProps(4, false, -2.7f, "asdf");
}
