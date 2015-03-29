/**
  * Contains functions for deserializing JSON data.
  *
  * Authors: <a href="https://github.com/rcorre">rcorre</a>
	* License: <a href="http://opensource.org/licenses/MIT">MIT</a>
	* Copyright: Copyright © 2015, rcorre
  * Date: 3/23/15
  */
module jsonizer.fromjson;

import std.json;
import std.conv;
import std.file;
import std.range;
import std.traits;
import std.string;
import std.algorithm;
import std.exception;
import std.typetuple;
import std.typecons : staticIota, Tuple;
import jsonizer.exceptions : JsonizeTypeException;
import jsonizer.internal.attribute;

/// json member used to map a json object to a D type
enum jsonizeClassKeyword = "class";

private void enforceJsonType(T)(JSONValue json, JSON_TYPE[] expected ...) {
  if (!expected.canFind(json.type)) {
    throw new JsonizeTypeException(typeid(T), json, expected);
  }
}

unittest {
  import std.exception : assertThrown, assertNotThrown;
  with (JSON_TYPE) {
    assertThrown!JsonizeTypeException(enforceJsonType!int(JSONValue("hi"), INTEGER, UINTEGER));
    assertThrown!JsonizeTypeException(enforceJsonType!(bool[string])(JSONValue([ 5 ]), OBJECT));
    assertNotThrown(enforceJsonType!int(JSONValue(5), INTEGER, UINTEGER));
    assertNotThrown(enforceJsonType!(bool[string])(JSONValue(["key": true]), OBJECT));
  }
}

deprecated("use fromJSON instead") {
  /// Deprecated: use `fromJSON` instead.
  T extract(T)(JSONValue json) {
    return json.fromJSON!T;
  }
}

/// Extract a boolean from a json value.
T fromJSON(T : bool)(JSONValue json) {
  if (json.type == JSON_TYPE.TRUE) {
    return true;
  }
  else if (json.type == JSON_TYPE.FALSE) {
    return false;
  }

  // expected 'true' or 'false'
  throw new JsonizeTypeException(typeid(bool), json, JSON_TYPE.TRUE, JSON_TYPE.FALSE);
}

/// Extract booleans from json values.
unittest {
  assert(JSONValue(false).fromJSON!bool == false);
  assert(JSONValue(true).fromJSON!bool == true);
}

/// Extract a string type from a json value.
T fromJSON(T : string)(JSONValue json) {
  if (json.type == JSON_TYPE.NULL) { return null; }
  enforceJsonType!T(json, JSON_TYPE.STRING);
  return cast(T) json.str;
}

/// Extract a string from a json string.
unittest {
  assert(JSONValue("asdf").fromJSON!string == "asdf");
}

/// Extract a numeric type from a json value.
T fromJSON(T : real)(JSONValue json) if (!is(T == enum)) {
  switch(json.type) {
    case JSON_TYPE.FLOAT:
      return cast(T) json.floating;
    case JSON_TYPE.INTEGER:
      return cast(T) json.integer;
    case JSON_TYPE.UINTEGER:
      return cast(T) json.uinteger;
    case JSON_TYPE.STRING:
      enforce(json.str.isNumeric, format("tried to extract %s from json string %s", T.stringof, json.str));
      return to!T(json.str); // try to parse string as int
    default:
  }

  throw new JsonizeTypeException(typeid(bool), json,
      JSON_TYPE.FLOAT, JSON_TYPE.INTEGER, JSON_TYPE.UINTEGER, JSON_TYPE.STRING);
}

/// Extract various numeric types.
unittest {
  assert(JSONValue(1).fromJSON!int      == 1);
  assert(JSONValue(2u).fromJSON!uint    == 2u);
  assert(JSONValue(3.0).fromJSON!double == 3.0);

  // fromJSON accepts numeric strings when a numeric conversion is requested
  assert(JSONValue("4").fromJSON!long   == 4L);
}

/// Extract an enumerated type from a json value.
T fromJSON(T)(JSONValue json) if (is(T == enum)) {
  enforceJsonType!T(json, JSON_TYPE.STRING);
  return to!T(json.str);
}

/// Convert a json string into an enum value.
unittest {
  enum Category { one, two }
  assert(JSONValue("one").fromJSON!Category == Category.one);
}

/// Extract an array from a JSONValue.
T fromJSON(T)(JSONValue json) if (isArray!T && !isSomeString!(T)) {
  if (json.type == JSON_TYPE.NULL) { return T.init; }
  enforceJsonType!T(json, JSON_TYPE.ARRAY);
  alias ElementType = ForeachType!T;
  T vals;
  foreach(idx, val ; json.array) {
    static if (isStaticArray!T) {
      vals[idx] = val.fromJSON!ElementType;
    }
    else {
      vals ~= val.fromJSON!ElementType;
    }
  }
  return vals;
}

/// Convert a json array into an array.
unittest {
  auto a = [ 1, 2, 3 ];
  assert(JSONValue(a).fromJSON!(int[]) == a);
}

/// Extract an associative array from a JSONValue.
T fromJSON(T)(JSONValue json) if (isAssociativeArray!T) {
  static assert(is(KeyType!T : string), "toJSON requires string keys for associative array");
  if (json.type == JSON_TYPE.NULL) { return null; }
  enforceJsonType!T(json, JSON_TYPE.OBJECT);
  alias ValType = ValueType!T;
  T map;
  foreach(key, val ; json.object) {
    map[key] = fromJSON!ValType(val);
  }
  return map;
}

/// Convert a json object to an associative array.
unittest {
  auto aa = ["a": 1, "b": 2];
  assert(JSONValue(aa).fromJSON!(int[string]) == aa);
}

/// Extract a value from a json object by its key.
T fromJSON(T)(JSONValue json, string key) {
  enforceJsonType!T(json, JSON_TYPE.OBJECT);
  enforce(key in json.object, "tried to extract non-existent key " ~ key ~ " from JSONValue");
  return fromJSON!T(json.object[key]);
}

unittest {
  auto aa = ["a": 1, "b": 2];
  auto json = JSONValue(aa);
  assert(json.fromJSON!int("a") == 1);
  assert(json.fromJSON!ulong("b") == 2L);
}

/// Extract a value from a json object by its key, return `defaultVal` if key not found.
T fromJSON(T)(JSONValue json, string key, T defaultVal) {
  enforceJsonType!T(json, JSON_TYPE.OBJECT);
  return (key in json.object) ? fromJSON!T(json.object[key]) : defaultVal;
}

/// Substitute default values when keys aren't present.
unittest {
  auto aa = ["a": 1, "b": 2];
  auto json = JSONValue(aa);
  assert(json.fromJSON!int("a", 7) == 1);
  assert(json.fromJSON!int("c", 7) == 7);
}

/// Read a json-constructable object from a file.
/// Params:
///   path = filesystem path to json file
/// Returns: object parsed from json file
T readJSON(T)(string path) {
  auto json = parseJSON(readText(path));
  return fromJSON!T(json);
}

/// Read a json file directly into a specified D type.
unittest {
  import std.path : buildPath;
  import std.uuid : randomUUID;
  import std.file : tempDir, write, mkdirRecurse;

  auto dir = buildPath(tempDir(), "jsonizer_readjson_test");
  mkdirRecurse(dir);
  auto file = buildPath(dir, randomUUID().toString);

  file.write("[1, 2, 3]");

  assert(file.readJSON!(int[]) == [ 1, 2, 3 ]);
}

/// Read contents of a json file directly into a JSONValue.
/// Params:
///   path = filesystem path to json file
/// Returns: a `JSONValue` parsed from the file
auto readJSON(string path) {
  return parseJSON(readText(path));
}

/// Read a json file into a JSONValue.
unittest {
  import std.path : buildPath;
  import std.uuid : randomUUID;
  import std.file : tempDir, write, mkdirRecurse;

  auto dir = buildPath(tempDir(), "jsonizer_readjson_test");
  mkdirRecurse(dir);
  auto file = buildPath(dir, randomUUID().toString);

  file.write("[1, 2, 3]");

  auto json = file.readJSON();

  assert(json.array[0].integer == 1);
  assert(json.array[1].integer == 2);
  assert(json.array[2].integer == 3);
}

/// Extract a user-defined class or struct from a JSONValue.
/// See `jsonizer.jsonize` for info on how to mark your own types for serialization.
T fromJSON(T)(JSONValue json) if (!isBuiltinType!T) {
  static if (is(T == class)) {
    if (json.type == JSON_TYPE.NULL) { return null; }
  }
  enforceJsonType!T(json, JSON_TYPE.OBJECT);

  // TODO: typeof(null) -- correct check here? is(T == class)?
  // maybe will not be necessary after rework of dynamic construction (remove use of factory).
  static if (is(typeof(null) : T) && is(typeof(T.init.populateFromJSON)))
  {
    // look for class keyword in json
    auto className = json.fromJSON!string(jsonizeClassKeyword, null);
    // try creating an instance with Object.factory
    if (className !is null) {
      auto obj = Object.factory(className);
      assert(obj !is null, "failed to Object.factory " ~ className);
      auto instance = cast(T) obj;
      assert(instance !is null, "failed to cast " ~ className ~ " to " ~ T.stringof);
      instance.populateFromJSON(json);
      return instance;
    }
  }

  // next, try to find a contructor marked with @jsonize and call that
  static if (__traits(hasMember, T, "__ctor")) {
    alias Overloads = TypeTuple!(__traits(getOverloads, T, "__ctor"));
    foreach(overload ; Overloads) {
      static if (staticIndexOf!(jsonize, __traits(getAttributes, overload)) >= 0) {
        if (canSatisfyCtor!overload(json)) {
          return invokeCustomJsonCtor!(T, overload)(json);
        }
      }
    }
  }

  // if no @jsonized ctor, try to use a default ctor and populate the fields
  static if(is(T == struct) || is(typeof(new T) == T)) { // can object be default constructed?
    return invokeDefaultCtor!(T)(json);
  }

  assert(0, T.stringof ~ " must have a no-args constructor to support extract");
}

/// Deserialize an instance of a user-defined type from a json object.
unittest {
  import jsonizer.jsonize;
  import jsonizer.tojson;

  static struct Foo {
    mixin JsonizeMe;

    @jsonize {
      int i;
      string[] a;
    }
  }

  auto jstr = q{
    {
      "i": 1,
      "a": [ "a", "b" ]
    }
  };

  // you could use `readJSON` instead of `parseJSON.fromJSON`
  auto foo = jstr.parseJSON.fromJSON!Foo;
  assert(foo.i == 1);
  assert(foo.a == [ "a", "b" ]);
}

// return true if keys can satisfy parameter names
private bool canSatisfyCtor(alias Ctor)(JSONValue json) {
  auto obj = json.object;
  alias Params   = ParameterIdentifierTuple!Ctor;
  alias Types    = ParameterTypeTuple!Ctor;
  alias Defaults = ParameterDefaultValueTuple!Ctor;
  foreach(i ; staticIota!(0, Params.length)) {
    if (Params[i] !in obj && typeid(Defaults[i]) == typeid(void)) {
      return false; // param had no default value and was not specified
    }
  }
  return true;
}

private T invokeCustomJsonCtor(T, alias Ctor)(JSONValue json) {
  enum params    = ParameterIdentifierTuple!(Ctor);
  alias defaults = ParameterDefaultValueTuple!(Ctor);
  alias Types    = ParameterTypeTuple!(Ctor);
  Tuple!(Types) args;
  foreach(i ; staticIota!(0, params.length)) {
    enum paramName = params[i];
    if (paramName in json.object) {
      args[i] = json.object[paramName].fromJSON!(Types[i]);
    }
    else { // no value specified in json
      static if (is(defaults[i] == void)) {
        enforce(0, "parameter " ~ paramName ~ " has no default value and was not specified");
      }
      else {
        args[i] = defaults[i];
      }
    }
  }
  static if (is(T == class)) {
    return new T(args.expand);
  }
  else {
    return T(args.expand);
  }
}

private T invokeDefaultCtor(T)(JSONValue json) {
  T obj;
  static if (is(T == struct)) {
    obj = T.init;
  }
  else {
    obj = new T;
  }
  obj.populateFromJSON(json);
  return obj;
}

bool hasCustomJsonCtor(T)() {
  static if (__traits(hasMember, T, "__ctor")) {
    alias Overloads = TypeTuple!(__traits(getOverloads, T, "__ctor"));
    foreach(overload ; Overloads) {
      static if (staticIndexOf!(jsonize, __traits(getAttributes, overload)) >= 0) {
        return true;
      }
    }
  }
  return false;
}
