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
import jsonizer.exceptions : JsonizeTypeException, JsonizeConstructorException;
import jsonizer.internal.attribute;
import jsonizer.internal.util;

/// See `jsonizer.jsonize` for info on how to mark your own types for serialization.
T fromJSON(T)(JSONValue json, JsonizeOptions options = JsonizeOptions.init) {
  // enumeration
  static if (is(T == enum)) {
    enforceJsonType!T(json, JSON_TYPE.STRING);
    return to!T(json.str);
  }

  // boolean
  else static if (is(T : bool)) {
    if (json.type == JSON_TYPE.TRUE)
      return true;
    else if (json.type == JSON_TYPE.FALSE)
      return false;

    // expected 'true' or 'false'
    throw new JsonizeTypeException(typeid(bool), json, JSON_TYPE.TRUE, JSON_TYPE.FALSE);
  }

  // string
  else static if (is(T : string)) {
    if (json.type == JSON_TYPE.NULL) { return null; }
    enforceJsonType!T(json, JSON_TYPE.STRING);
    return cast(T) json.str;
  }

  // numeric
  else static if (is(T : real)) {
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

  // array
  else static if (isArray!T) {
    if (json.type == JSON_TYPE.NULL) { return T.init; }
    enforceJsonType!T(json, JSON_TYPE.ARRAY);
    alias ElementType = ForeachType!T;
    T vals;
    foreach(idx, val ; json.array) {
      static if (isStaticArray!T) {
        vals[idx] = val.fromJSON!ElementType(options);
      }
      else {
        vals ~= val.fromJSON!ElementType(options);
      }
    }
    return vals;
  }

  // associative array
  else static if (isAssociativeArray!T) {
    static assert(is(KeyType!T : string), "toJSON requires string keys for associative array");
    if (json.type == JSON_TYPE.NULL) { return null; }
    enforceJsonType!T(json, JSON_TYPE.OBJECT);
    alias ValType = ValueType!T;
    T map;
    foreach(key, val ; json.object) {
      map[key] = fromJSON!ValType(val, options);
    }
    return map;
  }

  // user-defined class or struct
  else static if (!isBuiltinType!T) {
    return fromJSONImpl!T(json, null, options);
  }

  // by the time we get here, we've tried pretty much everything
  else {
    static assert(0, "fromJSON can't handle a " ~ T.stringof);
  }
}

/// Extract booleans from json values.
unittest {
  assert(JSONValue(false).fromJSON!bool == false);
  assert(JSONValue(true).fromJSON!bool == true);
}

/// Extract a string from a json string.
unittest {
  assert(JSONValue("asdf").fromJSON!string == "asdf");
}

/// Extract various numeric types.
unittest {
  assert(JSONValue(1).fromJSON!int      == 1);
  assert(JSONValue(2u).fromJSON!uint    == 2u);
  assert(JSONValue(3.0).fromJSON!double == 3.0);

  // fromJSON accepts numeric strings when a numeric conversion is requested
  assert(JSONValue("4").fromJSON!long   == 4L);
}

/// Convert a json string into an enum value.
unittest {
  enum Category { one, two }
  assert(JSONValue("one").fromJSON!Category == Category.one);
}

/// Convert a json array into an array.
unittest {
  auto a = [ 1, 2, 3 ];
  assert(JSONValue(a).fromJSON!(int[]) == a);
}

/// Convert a json object to an associative array.
unittest {
  auto aa = ["a": 1, "b": 2];
  assert(JSONValue(aa).fromJSON!(int[string]) == aa);
}

/// Extract a value from a json object by its key.
T fromJSON(T)(JSONValue json,
              string key,
              JsonizeOptions options = JsonizeOptions.init)
{
  enforceJsonType!T(json, JSON_TYPE.OBJECT);
  enforce(key in json.object, "tried to extract non-existent key " ~ key ~ " from JSONValue");
  return fromJSON!T(json.object[key], options);
}

/// Directly extract values from an object by their keys.
unittest {
  auto aa = ["a": 1, "b": 2];
  auto json = JSONValue(aa);
  assert(json.fromJSON!int("a") == 1);
  assert(json.fromJSON!ulong("b") == 2L);
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

/// Extract a value from a json object by its key, return `defaultVal` if key not found.
T fromJSON(T)(JSONValue json,
              string key,
              T defaultVal,
              JsonizeOptions options = JsonizeOptions.init)
{
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

/// Convert a json value in its string representation into a type `T`
/// Params:
///    T    = target type
///    json = json string to deserialize
T fromJSONString(T)(string json, JsonizeOptions options = JsonizeOptions.init) {
  return fromJSON!T(json.parseJSON, options);
}

/// Use `fromJSONString` to parse from a json `string` rather than a `JSONValue`
unittest {
  assert(fromJSONString!(int[])("[1, 2, 3]") == [1, 2, 3]);
}

/// Read a json-constructable object from a file.
/// Params:
///   path = filesystem path to json file
/// Returns: object parsed from json file
T readJSON(T)(string path, JsonizeOptions options = JsonizeOptions.init) {
  auto json = parseJSON(readText(path));
  return fromJSON!T(json, options);
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

deprecated("use fromJSON instead") {
  /// Deprecated: use `fromJSON` instead.
  T extract(T)(JSONValue json) {
    return json.fromJSON!T;
  }
}

// really should be private, but gets used from the mixin
Inner nestedFromJSON(Inner, Outer)(JSONValue json,
                                   Outer outer,
                                   JsonizeOptions options = JsonizeOptions.init)
{
  return fromJSONImpl!Inner(json, outer, options);
}

private:
void enforceJsonType(T)(JSONValue json, JSON_TYPE[] expected ...) {
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

// Internal implementation of fromJSON for user-defined types
// If T is a nested class, pass the parent of type P
// otherwise pass null for the parent
T fromJSONImpl(T, P)(JSONValue json, P parent, JsonizeOptions options) {
  static if (is(typeof(null) : T)) {
    if (json.type == JSON_TYPE.NULL) { return null; }
  }

  // try constructing from a primitive type using a single-param constructor
  if (json.type != JSON_TYPE.OBJECT) {
    return invokePrimitiveCtor!T(json, parent);
  }

  static if (!isNested!T && is(T == class) && is(typeof(T.init.populateFromJSON)))
  {
    // look for class keyword in json
    auto className = json.fromJSON!string(options.classKey, null);
    // try creating an instance with Object.factory
    if (className !is null) {
      auto obj = Object.factory(className);
      assert(obj !is null, "failed to Object.factory " ~ className);
      auto instance = cast(T) obj;
      assert(instance !is null, "failed to cast " ~ className ~ " to " ~ T.stringof);
      instance.populateFromJSON(json, options);
      return instance;
    }
  }

  // next, try to find a contructor marked with @jsonize and call that
  static if (__traits(hasMember, T, "__ctor")) {
    alias Overloads = TypeTuple!(__traits(getOverloads, T, "__ctor"));
    foreach(overload ; Overloads) {
      static if (staticIndexOf!(jsonize, __traits(getAttributes, overload)) >= 0) {
        if (canSatisfyCtor!overload(json)) {
          return invokeCustomJsonCtor!(T, overload)(json, parent);
        }
      }
    }

    // no constructor worked, is default-construction an option?
    static if(!hasDefaultCtor!T) {
      // not default-constructable, need to fail here
      alias ctors = Filter!(isJsonized, __traits(getOverloads, T, "__ctor"));
      JsonizeConstructorException.doThrow!(T, ctors)(json);
    }
  }

  // if no @jsonized ctor, try to use a default ctor and populate the fields
  static if(hasDefaultCtor!T) {
    return invokeDefaultCtor!(T)(json, parent);
  }

  assert(0, "all attempts at deserializing " ~ fullyQualifiedName!T ~ " failed.");
}

// return true if keys can satisfy parameter names
bool canSatisfyCtor(alias Ctor)(JSONValue json) {
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

T invokeCustomJsonCtor(T, alias Ctor, P)(JSONValue json, P parent) {
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
  static if (isNested!T) {
    return constructNested!T(parent, args.expand);
  }
  else static if (is(T == class)) {
    return new T(args.expand);
  }
  else {
    return T(args.expand);
  }
}

Inner constructNested(Inner, Outer, Args ...)(Outer outer, Args args) {
  return outer.new Inner(args);
}

T invokeDefaultCtor(T, P)(JSONValue json, P parent) {
  T obj;

  static if (isNested!T) {
    obj = parent.new T;
  }
  else static if (is(T == struct)) {
    obj = T.init;
  }
  else {
    obj = new T;
  }

  obj.populateFromJSON(json);
  return obj;
}

alias isJsonized(alias member) = hasUDA!(member, jsonize);

unittest {
  static class Foo {
    @jsonize int i;
    @jsonize("s") string _s;
    @jsonize @property string sprop() { return _s; }
    @jsonize @property void sprop(string str) { _s = str; }
    float f;
    @property int iprop() { return i; }

    @jsonize this(string s) { }
    this(int i) { }
  }

  Foo f;
  static assert(isJsonized!(__traits(getMember, f, "i")));
  static assert(isJsonized!(__traits(getMember, f, "_s")));
  static assert(isJsonized!(__traits(getMember, f, "sprop")));
  static assert(isJsonized!(__traits(getMember, f, "i")));
  static assert(!isJsonized!(__traits(getMember, f, "f")));
  static assert(!isJsonized!(__traits(getMember, f, "iprop")));

  import std.typetuple : Filter;
  static assert(Filter!(isJsonized, __traits(getOverloads, Foo, "__ctor")).length == 1);
}

T invokePrimitiveCtor(T, P)(JSONValue json, P parent) {
  static if (__traits(hasMember, T, "__ctor")) {
    foreach(overload ; __traits(getOverloads, T, "__ctor")) {
      alias Types = ParameterTypeTuple!overload;

      // look for an @jsonized ctor with a single parameter
      static if (hasAttribute!(jsonize, overload) && Types.length == 1) {
        return construct!T(parent, json.fromJSON!(Types[0]));
      }
    }
  }

  assert(0, "No primitive ctor for type " ~ T.stringof);
}
