import std.stdio;
import geometry;
import entity;
import component;
import sprite;
import animator;
import jsonizer.helpers : readJSON;

private enum fileName = "entities.json";

void main() {
  auto entities = fileName.readJSON!(Entity[string]);
  auto player = entities["player"];
  writefln("Player at position <%d,%d>", player.position.x, player.position.y);
  foreach(component ; player.components) {
    writeln(component.stringify);
  }
}
