jsonizer: D language JSON serializer
===

The primary purpose of **jsonizer** is to automate the generation of methods
needed to serialize and deserialize user-defined D structs and classes from JSON
data. jsonizer is not a standalone json parser, but rather a convenience layer
on top of `std.json`, allowing you to more easily work with `JSONValue` objects.

To use jsonizer, the main components you ened to be aware of are
the methods `fromJSON!T` and `toJSON`, the attribute `@jsonize`, and the mixin
template `JsonizeMe`.

## Overview
Jsonizer consists of the following modules:

- `jsonizer.fromjson`
  - parse a `T` from a `JSONValue` using `fromJSON!T`
  - parse a `T` from a json file using `readJSON!T`
- `jsonizer.tojson`
  - convert a `T` to a `JSONValue` using `toJSON!T`
  - write a `T` to a json file using `writeJSON!T`
- `jsonizer.jsonize`
  - mixin `JsonizeMe` to enable json serialization for a user-defined type
  - use `@jsonize` to mark members for serialization
- `jsonizer.all`
  - imports `jsonizer.tojson`, `jsonizer.fromjson`, and `jsonizer.jsonize`

## fromJSON!T
`fromJSON!T` converts a `JSONValue` into an object of type `T`.

```d
import jsonizer.fromjson;
JSONValue json; // lets assume this has some data in it
int i             = json.fromJSON!int;
MyEnum e          = json.fromJSON!MyEnum;
MyStruct[] s      = json.fromJSON!(MyStruct[]);
MyClass[string] c = json.fromJSON!(MyClass[string]);
```

`fromJSON!T` will fail (with `enforce`) if the json object's type is not
something it knows how to convert to `T`.

For primitive types, `fromJSON` leans on the side of flexibility -- for example,
`fromJSON!int` on a json entry of type `string` will try to parse an `int` from
the `string`.

For user-defined types, you have to do a little work to set up your struct or
class for jsonizer.

## @jsonize and JsonizeMe
The simplest way to make your type support json serialization is to mark its
members with the `@jsonize` attribute and have `mixin JsonizeMe;` somewhere in
your type definition. For example:

```d
struct S {
  mixin JsonizeMe; // this is required to support jsonization

  @jsonize { // public serialized members
    int x;
    float f;
  }
  string dontJsonMe; // jsonizer won't touch members not marked with @jsonize
}
```

The above could be deserialized by calling `fromJSON!S` from a json object like:

```json
{ "x": 5, "f": 1.2 }
```

This is a good place to note that `jsonize` will not error if a member was not
specified in the json object, nor would it error if some extraneous key was
present.

Your struct could be converted back into a `JSONValue` by calling `toJSON` on an
instance of it.

jsonizer can do more than just convert public members though:

```d
struct S {
  mixin JsonizeMe; // this is required to support jsonization

  // jsonize can convert private members too.
  // by default, jsonizer looks for a key in the json matching the member name
  // you can change this by passing a string to @jsonize
  private @jsonize("f") float _f;

  // you can use properties for more complex serialization
  // this is useful for converting types that are non-primitive
  // but also not defined by you, like std.datetime's Date
  private Date _date;
  @property @jsonize {
    string date() { return dateToString(_date); }
    void date(string str) { _date = dateFromString(str); }
  }
}
```

Assuming `dateToString` and `dateFromString` are some functions you defined, the
above could be `fromJSON`ed from a json object looking like:

```json
{ "f": 2.1, "date": "2015-05-01" }
```

The above examples work on both classes and structs provided the following:

1. Your type mixes in `JsonizeMe`
2. Your members are marked with `@jsonize`
3. Your type has a no-args constructor

### Optional members
By default, if a matching json entry is not found for a member marked with `@jsonize`,
deserialization will fail.
If this is not desired for a given member, mark it with `JsonizeOptional`.

```d
class MyClass {
  @jsonize int i;
  @jsonize(JsonizeOptional.yes) float f;
}
```

In the above example `json.fromJSON!MyClass` will fail if it does not find a key named "i" in the
json object, but will silently ignore the abscence of a key "f".

The way @jsonize takes parameters is rather flexible. While I can't condone making your class look
like the below example, it demonstrates the flexibility of @jsonize:

```d
class TotalMess {
  @jsonize(JsonizeOptional.yes) {
    @jsonize("i") int _i;
    @jsonize("f", JsonizeOptional.no) float _f;
    @jsonize(JsonizeOptional.no, "s") float _s;
  }
}
```

As the above shows, parameters may be passed in any order to @jsonize.

### Extra Members
If you would like to ensure that every entry in a json object is being
deserialized, you can pass `JsonizeIgnoreExtraKeys.no` to `JsonizeMe`.
In the example below, `fromJSON!S(jobject)` will `enforce` that no fields other
than `s` and `i` exist in `jobject`.

```d
struct S {
  mixin JsonizeMe(JsonizeIgnoreExtraKeys.no);
  string s;
  int i;
}
```

## Constructors
In some cases, #3 above may not seem so great. What if your type needs to
support serialization but shouldn't have a default constructor?
In this case, you want to `@jsonize` your constructor:

```d
class Custom {
  mixin JsonizeMe;

  @jsonize this(int i, string s = "hello") {
    _i = i;
    _s = s;
  }

  private:
  @jsonize("i") int    _i;
  @jsonize("s") string _s;
}
```

Given a type `T` with one or more constructors tagged with `@jsonize`,
`fromJSON!T` will try to match the member names and types to a constructor and
invoke that with the corresponding values from the json object.
Parameters with default values are considered optional; if they are not found in
the json, the default value will be used. The above example could be constructed
from json looking like:

```json
{ "i": 5, "s": "hi" }
```

If "s" were not present, it would be assigned the value "hello".

Note that while you can `@jsonize` multiple constructors, there should be no
overlap between situations that could satisfy them. If a given json object could
possibly match multiple constructors, jsonizer chooses arbitrarily (it does not
attempt to pick the 'most appropriate' constructor).

The method of jsonizing your constructor is also useful for types that need to
perform a more complex setup sequence.

Also note that when using `@jsonize` constructors, mixing in `JsonizeMe` and
marking members with `@jsonize` are only necessary for serialization -- if your
object only needs to support deserialization, marking a constructor is
sufficient.

## Factory construction
This is one of the newer and least tested features of jsonizer.
Suppose you have the following classes:

```d
module test;
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
```

and the following json:

```json
[
  {
    "class": "test.TestCompA",
     "c": 1,
     "a": 5
  },
  {
    "class": "test.TestCompB",
    "c": 2,
    "b": "hello"
  }
]
```

Calling `fromJSON!(TestComponent[])` on a `JSONValue` parsed from the above json
string should yield a TestComponent[] of length 2.
While both have the static type `TestComponent`, one is actually a `TestCompA`
and the other is a `TestCompB`, both with their fields appropriately populated.

Behind the scenes, jsonizer looks for a special key 'class' in the json (chosen
because class is a D keyword and could not be a member of your type). If it
finds this, it calls Object.factory using the specified string. It then calls
`populateFromJSON`, which is a method generated by the `JsonizeMe` mixin.

For this to work, your type must:
1. Have a default constructor
2. mixin JsonizeMe in **every** class in the hierarchy
