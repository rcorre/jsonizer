/// serialize and deserialize between JSONValues and other D types
module jsonizer;

import std.json;
import std.file;
import std.conv;
import std.range;
import std.traits;
import std.string;
import std.algorithm;
import std.exception;
import std.typetuple;
import std.typecons : staticIota;

/// json member used to map a json object to a D type  
enum jsonizeClassKeyword = "class";

/// use @jsonize to mark members to be (de)serialized from/to json
/// use @jsonize to mark a single contructor to use when creating an object using extract
/// use @jsonize("name") to make a member use the json key "name"
struct jsonize {
  string key;
}

// Primitive Type Conversions -----------------------------------------------------------
/// convert a bool to a JSONValue
JSONValue toJSON(T : bool)(T val) {
  return JSONValue(val);
}

/// convert a string to a JSONValue
JSONValue toJSON(T : string)(T val) {
  return JSONValue(val);
}

/// convert a floating point value to a JSONValue
JSONValue toJSON(T : real)(T val) if (!is(T == enum)) {
  return JSONValue(val);
}

/// convert a signed integer to a JSONValue
JSONValue toJSON(T : long)(T val) if (isSigned!T && !is(T == enum)) {
  return JSONValue(val);
}

/// convert an unsigned integer to a JSONValue
JSONValue toJSON(T : ulong)(T val) if (isUnsigned!T && !is(T == enum)) {
  return JSONValue(val);
}

/// convert an enum name to a JSONValue
JSONValue toJSON(T)(T val) if (is(T == enum)) {
  JSONValue json;
  json.str = to!string(val);
  return json;
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

JSONValue toJSON(T)(T obj) if (!isBuiltinType!T) {
  static if (is (T == class)) {
    if (obj is null) { return JSONValue(null); }
  }
  return obj.convertToJSON();
}

// Extraction ------------------------------------------------------------------
private void enforceJsonType(T)(JSONValue json, JSON_TYPE[] expected ...) {
  enum fmt = "extract!%s expected json type to be one of %s but got json type %s. json input: %s";
  enforce(expected.canFind(json.type), format(fmt, typeid(T), expected, json.type, json));
}

/// extract a boolean from a json value
T extract(T : bool)(JSONValue json) {
  if (json.type == JSON_TYPE.TRUE) {
    return true;
  }
  else if (json.type == JSON_TYPE.FALSE) {
    return false;
  }
  else {
    enforce(0, format("tried to extract bool from json of type %s", json.type));
  }
}

/// extract a string type from a json value
T extract(T : string)(JSONValue json) {
  if (json.type == JSON_TYPE.NULL) { return null; }
  enforceJsonType!T(json, JSON_TYPE.STRING);
  return cast(T) json.str;
}

/// extract a numeric type from a json value
T extract(T : real)(JSONValue json) if (!is(T == enum)) {
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
T extract(T)(JSONValue json) if (is(T == enum)) {
  enforceJsonType!T(json, JSON_TYPE.STRING);
  return to!T(json.str);
}

/// extract an array from a JSONValue
T extract(T)(JSONValue json) if (isArray!T && !isSomeString!(T)) {
  if (json.type == JSON_TYPE.NULL) { return T.init; }
  enforceJsonType!T(json, JSON_TYPE.ARRAY);
  alias ElementType = ForeachType!T;
  T vals;
  foreach(idx, val ; json.array) {
    static if (isStaticArray!T) {
      vals[idx] = val.extract!ElementType;
    }
    else {
      vals ~= val.extract!ElementType;
    }
  }
  return vals;
}

/// extract an associative array from a JSONValue
T extract(T)(JSONValue json) if (isAssociativeArray!T) {
  assert(is(KeyType!T : string), "toJSON requires string keys for associative array");
  if (json.type == JSON_TYPE.NULL) { return null; }
  enforceJsonType!T(json, JSON_TYPE.OBJECT);
  alias ValType = ValueType!T;
  T map;
  foreach(key, val ; json.object) {
    map[key] = extract!ValType(val);
  }
  return map;
}

/// extract a value from a json object by its key
T extract(T)(JSONValue json, string key) {
  enforceJsonType!T(json, JSON_TYPE.OBJECT);
  enforce(key in json.object, "tried to extract non-existent key " ~ key ~ " from JSONValue");
  return extract!T(json.object[key]);
}

/// extract a value from a json object by its key, return defaultVal if key not found
T extract(T)(JSONValue json, string key, T defaultVal) {
  enforceJsonType!T(json, JSON_TYPE.OBJECT);
  return (key in json.object) ? extract!T(json.object[key]) : defaultVal;
}

/// extract a user-defined class or struct from a JSONValue
T extract(T)(JSONValue json) if (!isBuiltinType!T) {
  static if (is(T == class)) {
    if (json.type == JSON_TYPE.NULL) { return null; }
  }
  enforceJsonType!T(json, JSON_TYPE.OBJECT);

  static if(is(typeof(new T) == T)) { // can object be default constructed?
    auto className = json.extract!string(jsonizeClassKeyword, null);
    if (className !is null) {
      auto instance = cast(T) Object.factory(className);
      assert(instance !is null, "failed to Object.factory " ~ className);
      instance.populateFromJSON(json);
      return instance;
    }
  }

  // next, try to find a contructor marked with @jsonize and call that
  static if (__traits(hasMember, T, "__ctor")) {
    alias Overloads = TypeTuple!(__traits(getOverloads, T, "__ctor"));
    foreach(overload ; Overloads) {
      if (staticIndexOf!(jsonize, __traits(getAttributes, overload)) >= 0 &&
          canSatisfyCtor!overload(json)) {
        return invokeCustomJsonCtor!(T, overload)(json);
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
      args[i] = json.object[paramName].extract!(Types[i]);
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

string jsonizeKey(alias obj, string memberName)() {
  foreach(attr ; __traits(getAttributes, mixin("obj." ~ memberName))) {
    static if (is(attr == jsonize)) { // @jsonize someMember;
      return memberName;          // use member name as-is
    }
    else static if (is(typeof(attr) == jsonize)) { // @jsonize("someKey") someMember;
      return attr.key;
    }
  }
  return null;
} 

mixin template JsonizeMe() {
  import std.json      : JSONValue;
  import std.typetuple : Erase;
  import std.traits    : BaseClassesTuple;

  alias T = typeof(this);
  static if (is(T == class) && 
      __traits(hasMember, BaseClassesTuple!T[0], "populateFromJSON")) 
  {
    override void populateFromJSON(JSONValue json) {
      static if (!hasCustomJsonCtor!T) {
        auto keyValPairs = json.object;
        // check if each member is actually a member and is marked with the @jsonize attribute
        foreach(member ; Erase!("__ctor", __traits(allMembers, T))) {
          enum key = jsonizeKey!(this, member);              // find @jsonize, deduce member key
          static if (key !is null) {
            alias MemberType = typeof(mixin(member));        // deduce member type
            auto val = extract!MemberType(keyValPairs[key]); // extract value from json
            mixin(member ~ "= val;");                        // assign value to member
          }
        }
      }
    }

    override JSONValue convertToJSON() {
      JSONValue[string] keyValPairs;
      // look for members marked with @jsonize, ignore __ctor
      foreach(member ; Erase!("__ctor", __traits(allMembers, T))) {
        enum key = jsonizeKey!(this, member); // find @jsonize, deduce member key
        static if(key !is null) {
          auto val = mixin(member);           // get the member's value
          keyValPairs[key] = toJSON(val);     // add the pair <memberKey> : <memberValue>
        }
      }
      // construct the json object
      JSONValue json;
      json.object = keyValPairs;
      return json;
    }
  }
  else {
    void populateFromJSON(JSONValue json) {
      static if (!hasCustomJsonCtor!T) {
        auto keyValPairs = json.object;
        // check if each member is actually a member and is marked with the @jsonize attribute
        foreach(member ; Erase!("__ctor", __traits(allMembers, T))) {
          enum key = jsonizeKey!(this, member);              // find @jsonize, deduce member key
          static if (key !is null) {
            alias MemberType = typeof(mixin(member));        // deduce member type
            auto val = extract!MemberType(keyValPairs[key]); // extract value from json
            mixin(member ~ "= val;");                        // assign value to member
          }
        }
      }
    }

    JSONValue convertToJSON() {
      JSONValue[string] keyValPairs;
      // look for members marked with @jsonize, ignore __ctor
      foreach(member ; Erase!("__ctor", __traits(allMembers, T))) {
        enum key = jsonizeKey!(this, member); // find @jsonize, deduce member key
        static if(key !is null) {
          auto val = mixin(member);           // get the member's value
          keyValPairs[key] = toJSON(val);     // add the pair <memberKey> : <memberValue>
        }
      }
      // construct the json object
      JSONValue json;
      json.object = keyValPairs;
      return json;
    }
  }
}

// Reading/Writing JSON Files
/// read a json-constructable object from a file
T readJSON(T)(string file) {
  auto json = parseJSON(readText(file));
  return extract!T(json);
}

/// shortcut to read file directly into JSONValue
auto readJSON(string file) {
  return parseJSON(readText(file));
}

/// write a jsonizeable object to a file
void writeJSON(T)(T obj, string file) {
  auto json = toJSON!T(obj);
  file.write(json.toPrettyString);
}

/// json conversion of primitive types
unittest {
  import std.math : approxEqual;
  enum Category { one, two }

  auto j1 = toJSON("bork");
  assert(j1.type == JSON_TYPE.STRING && j1.str == "bork");
  assert(extract!string(j1) == "bork");

  auto j2 = toJSON(4.1);
  assert(j2.type == JSON_TYPE.FLOAT && j2.floating.approxEqual(4.1));
  assert(extract!float(j2).approxEqual(4.1));
  assert(extract!double(j2).approxEqual(4.1));
  assert(extract!real(j2).approxEqual(4.1));

  auto j3 = toJSON(41);
  assert(j3.type == JSON_TYPE.INTEGER && j3.integer == 41);
  assert(extract!int(j3) == 41);
  assert(extract!long(j3) == 41);

  auto j4 = toJSON(41u);
  assert(j4.type == JSON_TYPE.UINTEGER && j4.uinteger == 41u);
  assert(extract!uint(j4) == 41u);
  assert(extract!ulong(j4) == 41u);

  auto jenum = toJSON!Category(Category.one);
  assert(jenum.type == JSON_TYPE.STRING);
  assert(jenum.extract!Category == Category.one);

  // homogenous json array
  auto j5 = toJSON([9, 8, 7, 6]);
  assert(j5.array[0].integer == 9);
  assert(j5.array[1].integer == 8);
  assert(j5.array[2].integer == 7);
  assert(j5.array[3].integer == 6);
  assert(j5.type == JSON_TYPE.ARRAY);
  assert(extract!(int[])(j5) == [9, 8, 7, 6]);

  // heterogenous json array
  auto j6 = toJSON("sammich", 1.5, 2, 3u);
  assert(j6.array[0].str == "sammich");
  assert(j6.array[1].floating.approxEqual(1.5));
  assert(j6.array[2].integer == 2);
  assert(j6.array[3].uinteger == 3u);

  // associative array
  int[string] aa = ["a" : 1, "b" : 2, "c" : 3];
  auto j7 = toJSON(aa);
  assert(j7.type == JSON_TYPE.OBJECT);
  assert(j7.object["a"].integer == 1);
  assert(j7.object["b"].integer == 2);
  assert(j7.object["c"].integer == 3);
  assert(extract!(int[string])(j7) == aa);
  assert(j7.extract!int("b") == 2);
}

/// object serialization -- fields only
unittest {
  import std.math : approxEqual;

  static class Fields {
    this() { } // class must have a no-args ctor

    this(int iVal, float fVal, string sVal, int[] aVal, string noJson) {
      i = iVal;
      f = fVal;
      s = sVal;
      a = aVal;
      dontJsonMe = noJson;
    }

    mixin JsonizeMe;

    @jsonize { // fields to jsonize -- test different access levels
      public int i;
      protected float f;
      public int[] a;
      private string s;
    }
    string dontJsonMe;

    override bool opEquals(Object o) {
      auto other = cast(Fields) o;
      return i == other.i && s == other.s && a == other.a && f.approxEqual(other.f);
    }
  }

  auto obj = new Fields(1, 4.2, "tally ho!", [9, 8, 7, 6], "blarg");
  auto json = toJSON!Fields(obj);

  assert(json.object["i"].integer == 1);
  assert(json.object["f"].floating.approxEqual(4.2));
  assert(json.object["s"].str == "tally ho!");
  assert(json.object["a"].array[0].integer == 9);
  assert("dontJsonMe" !in json.object);

  // reconstruct from json
  auto r = extract!Fields(json);
  assert(r.i == 1);
  assert(r.f.approxEqual(4.2));
  assert(r.s == "tally ho!");
  assert(r.a == [9, 8, 7, 6]);
  assert(r.dontJsonMe is null);

  // array of objects
  auto a = [
    new Fields(1, 4.2, "tally ho!", [9, 8, 7, 6], "blarg"),
        new Fields(7, 42.2, "yea merrily", [1, 4, 6, 4], "asparagus")
  ];

  // serialize array of user objects to json
  auto jsonArray = toJSON!(Fields[])(a);
  // reconstruct from json
  assert(extract!(Fields[])(jsonArray) == a);
}

/// object serialization with properties
unittest {
  import std.math : approxEqual;

  static class Props {
    this() { } // class must have a no-args ctor

    this(int iVal, float fVal, string sVal, string noJson) {
      _i = iVal;
      _f = fVal;
      _s = sVal;
      _dontJsonMe = noJson;
    }

    mixin JsonizeMe;

    @property {
      // jsonize ref property accessing private field
      @jsonize ref int i() { return _i; }
      // jsonize property with non-trivial get/set methods
      @jsonize float f() { return _f - 3; } // the jsonized value will equal _f - 3
      float f(float val) { return _f = val + 5; } // 5 will be added to _f when retrieving from json
      // don't jsonize these properties
      ref string s() { return _s; }
      ref string dontJsonMe() { return _dontJsonMe; }
    }

    private:
    int _i;
    float _f;
    @jsonize string _s;
    string _dontJsonMe;
  }

  auto obj = new Props(1, 4.2, "tally ho!", "blarg");
  auto json = toJSON(obj);

  assert(json.object["i"].integer == 1);
  assert(json.object["f"].floating.approxEqual(4.2 - 3.0)); // property should have subtracted 3 on retrieval
  assert(json.object["_s"].str == "tally ho!");
  assert("dontJsonMe" !in json.object);

  auto r = extract!Props(json);
  assert(r.i == 1);
  assert(r._f.approxEqual(4.2 - 3.0 + 5.0)); // property accessor should add 5
  assert(r._s == "tally ho!");
  assert(r.dontJsonMe is null);
}

/// object serialization with custom constructor
unittest {
  import std.math : approxEqual;

  static class Custom {
    mixin JsonizeMe;

    this(int i) {
      _i = i;
      _s = "something";
      _f = 10.2;
    }

    @jsonize this(int _i, string _s, float _f = 20.2) {
      this._i = _i;
      this._s = _s ~ " jsonized";
      this._f = _f;
    }

    @jsonize this(double d) { // alternate ctor
      _f = d.to!float;
      _s = d.to!string;
      _i = d.to!int;
    }

    private:
    @jsonize {
      string _s;
      float _f;
      int _i;
    }
  }

  auto c = new Custom(12);
  auto json = toJSON(c);
  assert(json.object["_i"].integer == 12);
  assert(json.object["_s"].str == "something");
  assert(json.object["_f"].floating.approxEqual(10.2));
  auto c2 = extract!Custom(json);
  assert(c2._i == 12);
  assert(c2._s == "something jsonized");
  assert(c2._f.approxEqual(10.2));

  // test alternate ctor
  json = parseJSON(`{"d" : 5}`);
  c = json.extract!Custom;
  assert(c._f.approxEqual(5) && c._i == 5 && c._s == "5");
}

/// struct serialization
unittest {
  import std.math : approxEqual;

  static struct S {
    mixin JsonizeMe;

    @jsonize {
      int x;
      float f;
      string s;
    }
    int dontJsonMe;

    this(int x, float f, string s, int noJson) {
      this.x = x;
      this.f = f;
      this.s = s;
      this.dontJsonMe = noJson;
    }
  }

  auto s = S(5, 4.2, "bogus", 7);
  auto json = toJSON(s); // serialize a struct

  assert(json.object["x"].integer == 5);
  assert(json.object["f"].floating.approxEqual(4.2));
  assert(json.object["s"].str == "bogus");
  assert("dontJsonMe" !in json.object);

  auto r = extract!S(json);
  assert(r.x == 5);
  assert(r.f.approxEqual(4.2));
  assert(r.s == "bogus");
  assert(r.dontJsonMe == int.init);
}

/// json file I/O
unittest {
  enum file = "test.json";
  scope(exit) remove(file);

  static struct Data {
    mixin JsonizeMe;

    @jsonize {
      int x;
      string s;
      float f;
    }
  }

  // write an array of user-defined structs
  auto array = [Data(5, "preposterous", 12.7), Data(8, "tesseract", -2.7), Data(5, "baby sloths", 102.7)];
  writeJSON(array, file);
  auto readBack = readJSON!(Data[])(file);
  assert(readBack == array);

  // now try an associative array
  auto aa = ["alpha": Data(27, "yams", 0), "gamma": Data(88, "spork", -99.999)];
  writeJSON(aa, file);
  auto aaReadBack = readJSON!(Data[string])(file);
  assert(aaReadBack == aa);
}

/// inheritance
unittest {
  import std.math : approxEqual;
  static class Parent {
    mixin JsonizeMe;
    @jsonize {
      int x;
      string s;
    }
  }

  static class Child : Parent {
    mixin JsonizeMe;
    @jsonize {
      float f;
    }
  }

  auto c = new Child;
  c.x = 5;
  c.s = "hello";
  c.f = 2.1;

  auto json = c.toJSON;
  assert(json.extract!int("x") == 5);
  assert(json.extract!string("s") == "hello");
  assert(json.extract!float("f").approxEqual(2.1));

  auto child = json.extract!Child;
  assert(child.x == 5 && child.s == "hello" && child.f.approxEqual(2.1));

  auto parent = json.extract!Parent;
  assert(parent.x == 5 && parent.s == "hello");
}

/// inheritance with  ctors
unittest {
  import std.math : approxEqual;
  static class Parent {
    mixin JsonizeMe;

    @jsonize this(int x, string s) {
      _x = x;
      _s = s;
    }

    @jsonize @property {
      int x()    { return _x; }
      string s() { return _s; }
    }

    private:
    int _x;
    string _s;
  }

  static class Child : Parent {
    mixin JsonizeMe;

    @jsonize this(int x, string s, float f) {
      super(x, s);
      _f = f;
    }

    @jsonize @property {
      float f() { return _f; }
    }

    private:
    float _f;
  }

  auto c = new Child(5, "hello", 2.1);

  auto json = c.toJSON;
  assert(json.extract!int("x") == 5);
  assert(json.extract!string("s") == "hello");
  assert(json.extract!float("f").approxEqual(2.1));

  auto child = json.extract!Child;
  assert(child.x == 5 && child.s == "hello" && child.f.approxEqual(2.1));

  auto parent = json.extract!Parent;
  assert(parent.x == 5 && parent.s == "hello");
}

/// renamed members
unittest {
  static class Bleh {
    mixin JsonizeMe;
    private {
      @jsonize("x") int _x;
      @jsonize("s") string _s;
    }
  }

  auto b = new Bleh;
  b._x = 5;
  b._s = "blah";

  auto json = b.toJSON;

  assert(json.extract!int("x") == 5);
  assert(json.extract!string("s") == "blah");

  auto reconstruct = json.extract!Bleh;
  assert(reconstruct._x == b._x && reconstruct._s == b._s);
}


// unfortunately these test classes must be implemented outside the unittest
// as Object.factory (and ClassInfo.find) cannot work with nested classes
private {
  class TestComponent {
    mixin JsonizeMe;
    @jsonize int c;
  }

  class TestCompA : TestComponent {
    mixin JsonizeMe;
    @jsonize int a;
  }

  class TestCompB : TestComponent {
    mixin JsonizeMe;
    @jsonize string b;
  }
}

/// type inference
unittest {
  import std.traits : fullyQualifiedName;

  // need to use these because unittest is assigned weird name
  // normally would just be "modulename.classname"
  string classKeyA = fullyQualifiedName!TestCompA;
  string classKeyB = fullyQualifiedName!TestCompB;

  assert(Object.factory(classKeyA) !is null && Object.factory(classKeyB) !is null, 
      "cannot factory classes in unittest -- this is a problem with the test");

  auto data = `[
    {
      "class": "%s",
      "c": 1,
      "a": 5
    },
    {
      "class": "%s",
      "c": 2,
      "b": "hello"
    }
  ]`.format(classKeyA, classKeyB).parseJSON.extract!(TestComponent[]);

  auto a = cast(TestCompA) data[0];
  auto b = cast(TestCompB) data[1];

  assert(a !is null && a.c == 1 && a.a == 5);
  assert(b !is null && b.c == 2 && b.b == "hello");
}
