/**
  * Import all public modules for jsonizer.
  *
  * Authors: <a href="https://github.com/rcorre">rcorre</a>
  * License: <a href="http://opensource.org/licenses/MIT">MIT</a>
  * Copyright: Copyright © 2015, rcorre
  * Date: 3/23/15
  */
module jsonizer;

public import jsonizer.tojson;
public import jsonizer.fromjson;
public import jsonizer.jsonize;
public import jsonizer.common;
public import jsonizer.exceptions;

/// object serialization -- fields only
unittest {
  import std.math : approxEqual;

  static class Fields {
    // classes must have a no-args constructor
    // or a constructor marked with @jsonize (see later example)
    this() { }

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
  auto r = fromJSON!Fields(json);
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
  assert(fromJSON!(Fields[])(jsonArray) == a);
}

/++
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

  auto r = fromJSON!Props(json);
  assert(r.i == 1);
  assert(r._f.approxEqual(4.2 - 3.0 + 5.0)); // property accessor should add 5
  assert(r._s == "tally ho!");
  assert(r.dontJsonMe is null);
}

/// object serialization with custom constructor
unittest {
  import std.conv : to;
  import std.json : parseJSON;
  import std.math : approxEqual;
  import jsonizer.tojson : toJSON;

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
  auto c2 = fromJSON!Custom(json);
  assert(c2._i == 12);
  assert(c2._s == "something jsonized");
  assert(c2._f.approxEqual(10.2));

  // test alternate ctor
  json = parseJSON(`{"d" : 5}`);
  c = json.fromJSON!Custom;
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

  auto r = fromJSON!S(json);
  assert(r.x == 5);
  assert(r.f.approxEqual(4.2));
  assert(r.s == "bogus");
  assert(r.dontJsonMe == int.init);
}

/// json file I/O
unittest {
  import std.file          : remove;
  import jsonizer.fromjson : readJSON;
  import jsonizer.tojson   : writeJSON;

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
  file.writeJSON(array);
  auto readBack = file.readJSON!(Data[]);
  assert(readBack == array);

  // now try an associative array
  auto aa = ["alpha": Data(27, "yams", 0), "gamma": Data(88, "spork", -99.999)];
  file.writeJSON(aa);
  auto aaReadBack = file.readJSON!(Data[string]);
  assert(aaReadBack == aa);
}

/// inheritance
unittest {
  import std.math : approxEqual;
  static class Parent {
    mixin JsonizeMe;
    @jsonize int x;
    @jsonize string s;
  }

  static class Child : Parent {
    mixin JsonizeMe;
    @jsonize float f;
  }

  auto c = new Child;
  c.x = 5;
  c.s = "hello";
  c.f = 2.1;

  auto json = c.toJSON;
  assert(json.fromJSON!int("x") == 5);
  assert(json.fromJSON!string("s") == "hello");
  assert(json.fromJSON!float("f").approxEqual(2.1));

  auto child = json.fromJSON!Child;
  assert(child !is null);
  assert(child.x == 5 && child.s == "hello" && child.f.approxEqual(2.1));

  auto parent = json.fromJSON!Parent;
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
  assert(json.fromJSON!int("x") == 5);
  assert(json.fromJSON!string("s") == "hello");
  assert(json.fromJSON!float("f").approxEqual(2.1));

  auto child = json.fromJSON!Child;
  assert(child.x == 5 && child.s == "hello" && child.f.approxEqual(2.1));

  auto parent = json.fromJSON!Parent;
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

  assert(json.fromJSON!int("x") == 5);
  assert(json.fromJSON!string("s") == "blah");

  auto reconstruct = json.fromJSON!Bleh;
  assert(reconstruct._x == b._x && reconstruct._s == b._s);
}

// members that potentially conflict with variables used in the mixin
unittest {
  static struct Foo {
    mixin JsonizeMe;
    @jsonize int val;
  }

  Foo orig = Foo(3);
  auto serialized   = orig.toJSON;
  auto deserialized = serialized.fromJSON!Foo;

  assert(deserialized.val == orig.val);
}
++/
