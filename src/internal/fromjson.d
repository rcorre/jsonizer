/// `fromJSON!T` converts a `JSONValue` to an instance of `T`
module internal.fromjson;

import std.json;
import std.conv;
import std.range;
import std.traits;
import std.string;
import std.algorithm;
import std.exception;
import std.typetuple;
import std.typecons : staticIota;
import internal.attribute;

/// json member used to map a json object to a D type
enum jsonizeClassKeyword = "class";

private void enforceJsonType(T)(JSONValue json, JSON_TYPE[] expected ...) {
  enum fmt = "fromJSON!%s expected json type to be one of %s but got json type %s. json input: %s";
  enforce(expected.canFind(json.type), format(fmt, typeid(T), expected, json.type, json));
}

deprecated("use fromJSON instead") {
  T extract(T)(JSONValue json) {
    return json.fromJSON!T;
  }
}

/// extract a boolean from a json value
T fromJSON(T : bool)(JSONValue json) {
  if (json.type == JSON_TYPE.TRUE) {
    return true;
  }
  else if (json.type == JSON_TYPE.FALSE) {
    return false;
  }
  enforce(0, format("tried to extract bool from json of type %s", json.type));
  assert(0);
}

/// extract a string type from a json value
T fromJSON(T : string)(JSONValue json) {
  if (json.type == JSON_TYPE.NULL) { return null; }
  enforceJsonType!T(json, JSON_TYPE.STRING);
  return cast(T) json.str;
}

/// extract a numeric type from a json value
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
      enforce(0, format("tried to extract %s from json of type %s", T.stringof, json.type));
  }
  assert(0, "should not be reacheable");
}

/// extract an enumerated type from a json value
T fromJSON(T)(JSONValue json) if (is(T == enum)) {
  enforceJsonType!T(json, JSON_TYPE.STRING);
  return to!T(json.str);
}

/// extract an array from a JSONValue
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

/// extract an associative array from a JSONValue
T fromJSON(T)(JSONValue json) if (isAssociativeArray!T) {
  assert(is(KeyType!T : string), "toJSON requires string keys for associative array");
  if (json.type == JSON_TYPE.NULL) { return null; }
  enforceJsonType!T(json, JSON_TYPE.OBJECT);
  alias ValType = ValueType!T;
  T map;
  foreach(key, val ; json.object) {
    map[key] = fromJSON!ValType(val);
  }
  return map;
}

/// extract a value from a json object by its key
T fromJSON(T)(JSONValue json, string key) {
  enforceJsonType!T(json, JSON_TYPE.OBJECT);
  enforce(key in json.object, "tried to extract non-existent key " ~ key ~ " from JSONValue");
  return fromJSON!T(json.object[key]);
}

/// extract a value from a json object by its key, return defaultVal if key not found
T fromJSON(T)(JSONValue json, string key, T defaultVal) {
  enforceJsonType!T(json, JSON_TYPE.OBJECT);
  return (key in json.object) ? fromJSON!T(json.object[key]) : defaultVal;
}

/// extract a user-defined class or struct from a JSONValue
T fromJSON(T)(JSONValue json) if (!isBuiltinType!T) {
  static if (is(T == class)) {
    if (json.type == JSON_TYPE.NULL) { return null; }
  }
  enforceJsonType!T(json, JSON_TYPE.OBJECT);

  static if (is(typeof(null) : T)) {
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

/// return true if keys can satisfy parameter names
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
