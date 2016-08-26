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
import std.meta;
import std.range;
import std.traits;
import std.string;
import std.algorithm;
import std.exception;
import std.typetuple;
import std.typecons : staticIota, Tuple;
import jsonizer.exceptions;
import jsonizer.common;

// HACK: this is a hack to allow referencing this particular overload using
// &fromJSON!T in the JsonizeMe mixin
T _fromJSON(T)(JSONValue json,
               in ref JsonizeOptions options = JsonizeOptions.defaults)
{
  return fromJSON!T(json, options);
}

/**
 * Deserialize json into a value of type `T`.
 *
 * Params:
 *  T       = Target type. can be any primitive/builtin D type, or any
 *            user-defined type using the `JsonizeMe` mixin.
 *  json    = `JSONValue` to deserialize.
 *  options = configures the deserialization behavior.
 */
T fromJSON(T)(JSONValue json,
              in ref JsonizeOptions options = JsonizeOptions.defaults)
{
  // JSONValue -- identity
  static if (is(T == JSONValue))
      return json;

  // enumeration
  else static if (is(T == enum)) {
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

/// Convert a json object to a user-defined type.
/// See the docs for `JsonizeMe` for more detailed examples.
unittest {
  import jsonizer;
  static struct MyStruct {
    mixin JsonizeMe;

    @jsonize int i;
    @jsonize string s;
    float f;
  }

  auto json = `{ "i": 5, "s": "tally-ho!" }`.parseJSON;
  auto val = json.fromJSON!MyStruct;
  assert(val.i == 5);
  assert(val.s == "tally-ho!");
}

/**
 * Extract a value from a json object by its key.
 *
 * Throws if `json` is not of `JSON_TYPE.OBJECT` or the key does not exist.
 *
 * Params:
 *  T       = Target type. can be any primitive/builtin D type, or any
 *            user-defined type using the `JsonizeMe` mixin.
 *  json    = `JSONValue` to deserialize.
 *  key     = key of desired value within the object.
 *  options = configures the deserialization behavior.
 */
T fromJSON(T)(JSONValue json,
              string key,
              in ref JsonizeOptions options = JsonizeOptions.defaults)
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

/**
 * Extract a value from a json object by its key.
 *
 * Throws if `json` is not of `JSON_TYPE.OBJECT`.
 * Return `defaultVal` if the key does not exist.
 *
 * Params:
 *  T          = Target type. can be any primitive/builtin D type, or any
 *               user-defined type using the `JsonizeMe` mixin.
 *  json       = `JSONValue` to deserialize.
 *  key        = key of desired value within the object.
 *  defaultVal = value to return if key is not found
 *  options    = configures the deserialization behavior.
 */
T fromJSON(T)(JSONValue json,
              string key,
              T defaultVal,
              in ref JsonizeOptions options = JsonizeOptions.defaults)
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

/*
 * Convert a json value in its string representation into a type `T`
 * Params:
 *  T       = Target type. can be any primitive/builtin D type, or any
 *            user-defined type using the `JsonizeMe` mixin.
 *  json    = JSON-formatted string to deserialize.
 *  options = configures the deserialization behavior.
 */
T fromJSONString(T)(string json,
                    in ref JsonizeOptions options = JsonizeOptions.defaults)
{
  return fromJSON!T(json.parseJSON, options);
}

/// Use `fromJSONString` to parse from a json `string` rather than a `JSONValue`
unittest {
  assert(fromJSONString!(int[])("[1, 2, 3]") == [1, 2, 3]);
}

/**
 * Read a json-constructable object from a file.
 * Params:
 *  T       = Target type. can be any primitive/builtin D type, or any
 *            user-defined type using the `JsonizeMe` mixin.
 *  path    = filesystem path to json file
 *  options = configures the deserialization behavior.
 */
T readJSON(T)(string path,
              in ref JsonizeOptions options = JsonizeOptions.defaults)
{
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

/**
 * Read the contents of a json file directly into a `JSONValue`.
 * Params:
 *   path = filesystem path to json file
 */
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
T fromJSONImpl(T, P)(JSONValue json, P parent, in ref JsonizeOptions options) {
  static if (is(typeof(null) : T)) {
    if (json.type == JSON_TYPE.NULL) { return null; }
  }

  // try constructing from a primitive type using a single-param constructor
  if (json.type != JSON_TYPE.OBJECT) {
    return invokePrimitiveCtor!T(json, parent);
  }

  static if (!isNested!T && is(T == class))
  {
    // if the class is identified in the json, construct an instance of the
    // specified type
    auto className = json.fromJSON!string(options.classKey, null);
    if (options.classMap) {
        if(auto tmp = options.classMap(className))
          className = tmp;
    }
    if (className) {
      auto handler = className in T._jsonizeCtors;
      assert(handler, className ~ " not registered in " ~ T.stringof);
      JsonizeOptions newopts = options;
      newopts.classKey = null; // don't recursively loop looking up class name
      return (*handler)(json, newopts);
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
    return invokeDefaultCtor!T(json, parent, options);
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
  static if (isNested!T)
    return parent.new T(args.expand);
  else static if (is(T == class))
    return new T(args.expand);
  else
    return T(args.expand);
}

T invokeDefaultCtor(T, P)(JSONValue json, P parent, JsonizeOptions options) {
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

  populate(obj, json, options);
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
      static if (hasUDA!(overload, jsonize) && Types.length == 1) {
        return construct!T(parent, json.fromJSON!(Types[0]));
      }
    }
  }

  assert(0, "No primitive ctor for type " ~ T.stringof);
}

void populate(T)(ref T obj, JSONValue json, in JsonizeOptions opt) {
  string[] missingKeys;
  uint fieldsFound = 0;

  foreach (member ; T._membersWithUDA!jsonize) {
    string key = jsonKey!(T, member);

    auto required = JsonizeIn.unspecified;
    foreach (attr ; T._getUDAs!(member, jsonize))
      if (attr.perform_in != JsonizeIn.unspecified)
        required = attr.perform_in;

    if (required == JsonizeIn.no) continue;

    if (auto jsonval = key in json.object) {
      ++fieldsFound;
      alias MemberType = T._writeMemberType!member;

      static if (!is(MemberType == void)) {
        static if (isAggregateType!MemberType && isNested!MemberType)
          auto val = fromJSONImpl!Inner(*jsonval, obj, opt);
        else {
          auto val = fromJSON!MemberType(*jsonval, opt);
        }

        obj._writeMember!(MemberType, member)(val);
      }
    }
    else {
      if (required == JsonizeIn.yes) missingKeys ~= key;
    }
  }

  string[] extraKeys;
  if (!T._jsonizeIgnoreExtra && fieldsFound < json.object.length)
    extraKeys = json.object.keys.filter!(x => x.isUnknownKey!T).array;

  if (missingKeys.length > 0 || extraKeys.length > 0)
    throw new JsonizeMismatchException(typeid(T), extraKeys, missingKeys);
}

bool isUnknownKey(T)(string key) {
  foreach (member ; T._membersWithUDA!jsonize)
    if (jsonKey!(T, member) == key)
      return false;

  return true;
}

T construct(T, P, Params ...)(P parent, Params params) {
  static if (!is(P == typeof(null))) {
    return parent.new T(params);
  }
  else static if (is(typeof(T(params)) == T)) {
    return T(params);
  }
  else static if (is(typeof(new T(params)) == T)) {
    return new T(params);
  }
  else {
    static assert(0, "Cannot construct");
  }
}

unittest {
  static struct Foo {
    this(int i) { this.i = i; }
    int i;
  }

  assert(construct!Foo(null).i == 0);
  assert(construct!Foo(null, 4).i == 4);
  assert(!__traits(compiles, construct!Foo("asd")));
}

unittest {
  static class Foo {
    this(int i) { this.i = i; }

    this(int i, string s) {
      this.i = i;
      this.s = s;
    }

    int i;
    string s;
  }

  assert(construct!Foo(null, 4).i == 4);
  assert(construct!Foo(null, 4, "asdf").s == "asdf");
  assert(!__traits(compiles, construct!Foo("asd")));
}

unittest {
  class Foo {
    class Bar {
      int i;
      this(int i) { this.i = i; }
    }
  }

  auto f = new Foo;
  assert(construct!(Foo.Bar)(f, 2).i == 2);
}

template hasDefaultCtor(T) {
  static if (isNested!T) {
    alias P = typeof(__traits(parent, T).init);
    enum hasDefaultCtor = is(typeof(P.init.new T()) == T);
  }
  else {
    enum hasDefaultCtor = is(typeof(T()) == T) || is(typeof(new T()) == T);
  }
}

version(unittest) {
  struct S1 { }
  struct S2 { this(int i) { } }
  struct S3 { @disable this(); }

  class C1 { }
  class C2 { this(string s) { } }
  class C3 { class Inner { } }
  class C4 { class Inner { this(int i); } }
}

unittest {
  static assert( hasDefaultCtor!S1);
  static assert( hasDefaultCtor!S2);
  static assert(!hasDefaultCtor!S3);

  static assert( hasDefaultCtor!C1);
  static assert(!hasDefaultCtor!C2);

  static assert( hasDefaultCtor!C3);
  static assert( hasDefaultCtor!(C3.Inner));
  static assert(!hasDefaultCtor!(C4.Inner));
}

template hasCustomJsonCtor(T) {
  static if (__traits(hasMember, T, "__ctor")) {
    alias Overloads = TypeTuple!(__traits(getOverloads, T, "__ctor"));

    enum test(alias fn) = staticIndexOf!(jsonize, __traits(getAttributes, fn)) >= 0;

    enum hasCustomJsonCtor = anySatisfy!(test, Overloads);
  }
  else {
    enum hasCustomJsonCtor = false;
  }
}

unittest {
  static struct S1 { }
  static struct S2 { this(int i); }
  static struct S3 { @jsonize this(int i); }
  static struct S4 { this(float f); @jsonize this(int i); }

  static assert(!hasCustomJsonCtor!S1);
  static assert(!hasCustomJsonCtor!S2);
  static assert( hasCustomJsonCtor!S3);
  static assert( hasCustomJsonCtor!S4);

  static class C1 { }
  static class C2 { this() {} }
  static class C3 { @jsonize this() {} }
  static class C4 { @jsonize this(int i); this(float f); }

  static assert(!hasCustomJsonCtor!C1);
  static assert(!hasCustomJsonCtor!C2);
  static assert( hasCustomJsonCtor!C3);
  static assert( hasCustomJsonCtor!C4);
}
