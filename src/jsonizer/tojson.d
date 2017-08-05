/**
  * Contains functions for serializing JSON data.
  *
  * Authors: <a href="https://github.com/rcorre">rcorre</a>
  * License: <a href="http://opensource.org/licenses/MIT">MIT</a>
  * Copyright: Copyright © 2015, rcorre
  * Date: 3/23/15
  */
module jsonizer.tojson;

import std.json;
import std.traits;
import std.conv;
import std.file;
import std.exception;
import std.typecons;
import jsonizer.common;

/// convert a JSONValue to a JSONValue (identity)
JSONValue toJSON(JSONValue val) {
  return val;
}

/// convert a bool to a JSONValue
JSONValue toJSON(T : bool)(T val) {
  return JSONValue(val);
}

/// Serialize a boolean.
unittest {
  assert(false.toJSON == JSONValue(false));
  assert(true.toJSON == JSONValue(true));
}

/// convert a string to a JSONValue
JSONValue toJSON(T : string)(T val) {
  return JSONValue(val);
}

/// Serialize a string.
unittest {
  assert("bork".toJSON == JSONValue("bork"));
}

/// convert a floating point value to a JSONValue
JSONValue toJSON(T : real)(T val) if (!is(T == enum)) {
  return JSONValue(val);
}

/// Serialize a floating-point value.
unittest {
  assert(4.1f.toJSON == JSONValue(4.1f));
}

/// convert a signed integer to a JSONValue
JSONValue toJSON(T : long)(T val) if (isSigned!T && !is(T == enum)) {
  return JSONValue(val);
}

/// Serialize a signed integer.
unittest {
  auto j3 = toJSON(41);
  assert(4.toJSON == JSONValue(4));
  assert(4L.toJSON == JSONValue(4L));
}

/// convert an unsigned integer to a JSONValue
JSONValue toJSON(T : ulong)(T val) if (isUnsigned!T && !is(T == enum)) {
  return JSONValue(val);
}

/// Serialize an unsigned integer.
unittest {
  assert(41u.toJSON == JSONValue(41u));
}

/// convert an enum name to a JSONValue
JSONValue toJSON(T)(T val) if (is(T == enum)) {
  JSONValue json;
  json.str = to!string(val);
  return json;
}

/// Enums are serialized by name.
unittest {
  enum Category { one, two }

  assert(Category.one.toJSON.str == "one");
  assert(Category.two.toJSON.str == "two");
}

/// convert a homogenous array into a JSONValue array
JSONValue toJSON(T)(T args) if (isArray!T && !isSomeString!T) {
  static if (isDynamicArray!T) {
    if (args is null) { return JSONValue(null); }
  }
  JSONValue[] jsonVals;
  foreach(arg ; args) {
    jsonVals ~= toJSON(arg);
  }
  JSONValue json;
  json.array = jsonVals;
  return json;
}

/// Serialize a homogenous array.
unittest {
  auto json = [1, 2, 3].toJSON;
  assert(json.type == JSON_TYPE.ARRAY);
  assert(json.array[0].integer == 1);
  assert(json.array[1].integer == 2);
  assert(json.array[2].integer == 3);
}

/// convert a set of heterogenous values into a JSONValue array
JSONValue toJSON(T...)(T args) {
  JSONValue[] jsonVals;
  foreach(arg ; args) {
    jsonVals ~= toJSON(arg);
  }
  JSONValue json;
  json.array = jsonVals;
  return json;
}

/// Serialize a heterogenous array.
unittest {
  auto json = toJSON(1, "hi", 0.4);
  assert(json.type == JSON_TYPE.ARRAY);
  assert(json.array[0].integer  == 1);
  assert(json.array[1].str      == "hi");
  assert(json.array[2].floating == 0.4);
}

/// convert a associative array into a JSONValue object
JSONValue toJSON(T)(T map) if (isAssociativeArray!T) {
  assert(is(KeyType!T : string), "toJSON requires string keys for associative array");
  if (map is null) { return JSONValue(null); }
  JSONValue[string] obj;
  foreach(key, val ; map) {
    obj[key] = toJSON(val);
  }
  JSONValue json;
  json.object = obj;
  return json;
}

/// Serialize an associative array.
unittest {
  auto json = ["a" : 1, "b" : 2, "c" : 3].toJSON;
  assert(json.type == JSON_TYPE.OBJECT);
  assert(json.object["a"].integer == 1);
  assert(json.object["b"].integer == 2);
  assert(json.object["c"].integer == 3);
}

/// Convert a user-defined type to json.
/// See `jsonizer.jsonize` for info on how to mark your own types for serialization.
JSONValue toJSON(T)(T obj) if (!isBuiltinType!T) {
  static if (is (T == class))
    if (obj is null) { return JSONValue(null); }

  JSONValue[string] keyValPairs;

  foreach(member ; T._membersWithUDA!jsonize) {
    enum key = jsonKey!(T, member);

    auto output = JsonizeOut.unspecified;
    foreach (attr ; T._getUDAs!(member, jsonize))
      if (attr.perform_out != JsonizeOut.unspecified)
        output = attr.perform_out;

    if (output == JsonizeOut.no) continue;

    auto val = obj._readMember!member;
    if (output == JsonizeOut.opt && isInitial(val)) continue;

    keyValPairs[key] = toJSON(val);
  }

  std.json.JSONValue json;
  json.object = keyValPairs;
  return json;
}

/// Serialize an instance of a user-defined type to a json object.
unittest {
  import jsonizer.jsonize;

  static struct Foo {
    mixin JsonizeMe;
    @jsonize int i;
    @jsonize string[] a;
  }

  auto foo = Foo(12, [ "a", "b" ]);
  assert(foo.toJSON() == `{"i": 12, "a": [ "a", "b" ]}`.parseJSON);
}

/// Whether to nicely format json string.
alias PrettyJson = Flag!"PrettyJson";

/// Convert an instance of some type `T` directly into a json-formatted string.
/// Params:
///   T      = type of object to convert
///   obj    = object to convert to sjon
///   pretty = whether to prettify string output
string toJSONString(T)(T obj, PrettyJson pretty = PrettyJson.yes) {
  auto json = obj.toJSON!T;
  return pretty ? json.toPrettyString : json.toString;
}

unittest {
  assert([1, 2, 3].toJSONString(PrettyJson.no) == "[1,2,3]");
  assert([1, 2, 3].toJSONString(PrettyJson.yes) == "[\n    1,\n    2,\n    3\n]");
}

/// Write a jsonizeable object to a file.
/// Params:
///   path = filesystem path to write json to
///   obj  = object to convert to json and write to path
void writeJSON(T)(string path, T obj) {
  auto json = toJSON!T(obj);
  path.write(json.toPrettyString);
}

unittest {
  import std.path : buildPath;
  import std.uuid : randomUUID;

  auto dir = buildPath(tempDir(), "jsonizer_writejson_test");
  mkdirRecurse(dir);
  auto file = buildPath(dir, randomUUID().toString);

  file.writeJSON([1, 2, 3]);

  auto json = file.readText.parseJSON;
  assert(json.array[0].integer == 1);
  assert(json.array[1].integer == 2);
  assert(json.array[2].integer == 3);
}

// True if `val` is equal to the initial value of that type
bool isInitial(T)(T val)
{
  static if (is(typeof(val == T.init)))
    return val == T.init;
  else static if (is(typeof(val is T.init)))
    return val is T.init;
  else static assert(0, "isInitial can't handle " ~ T.stringof);
}
