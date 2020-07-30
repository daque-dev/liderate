module liderate.treelan.parser;

import std.variant: Algebraic;
struct Command
{
  string name;
  string unnamedArgument;
  string[string] namedArguments;
}
alias LineOrCommand = Algebraic!(string, Command);

LineOrCommand parse(string line)
{
  line = line.dup;

  import std.string: split;
  auto words = line.split;
  if (words.length == 0 || words[0][0] != '@')
    return LineOrCommand(line);

  Command command;
  string lastNamed = null;
  command.name = words[0][1 .. $];
  foreach(word; words[1 .. $])
    {
      assert(word.length > 0);
      if (word[0] == '.')
        {
          lastNamed = word[1 .. $];
          command.namedArguments[lastNamed] = "";
          continue;
        }
      if (lastNamed !is null)
        {
          if (command.namedArguments[lastNamed].length > 0)
            command.namedArguments[lastNamed] ~= " " ~ word;
          else
            command.namedArguments[lastNamed] ~= word;
          continue;
        }
      if (command.unnamedArgument.length == 0)
        command.unnamedArgument ~= word;
      else
        command.unnamedArgument ~= " " ~ word;
    }
  return LineOrCommand(command);
}

class ParentNode
{
  string name;
  string[string] parameters;
  Node[] children;
  ParentNode parent;
}
alias Node = Algebraic!(string, ParentNode);

import std.container: SList;
SList!ParentNode parentNodes;

void process(LineOrCommand lineOrCommand)
{
  import std.variant: visit;
  lineOrCommand.visit!((string line)
                       {
                         assert(!parentNodes.empty);
                         parentNodes.front.children ~= Node(line);
                         return;
                       },
                       (Command command)
                       {
                         process(command);
                       });
}

void process(Command command)
{
  switch(command.name)
    {
    case "[":
      assert(!parentNodes.empty);
      ParentNode newNode = new ParentNode();
      with(newNode)
        {
          name = command.unnamedArgument;
          parameters = command.namedArguments;
          children = [];
          parent = parentNodes.front;
        }
      parentNodes.front.children ~= Node(newNode);
      parentNodes.insertFront(newNode);
      break;
    case "]":
      assert(!parentNodes.empty);
      parentNodes.removeFront;
      break;
    case "[]":
      assert(!parentNodes.empty);
      ParentNode newNode = new ParentNode();
      with(newNode)
        {
          name = command.unnamedArgument;
          parameters = command.namedArguments;
          children = [];
          parent = parentNodes.front;
        }
      parentNodes.front.children ~= Node(newNode);
      break;
    default:
      assert(0, "Unknown command " ~ command.name);
    }
}

import std.stdio: File;
void toDotGraph(File file, ParentNode rootNode)
{
  import std.variant: visit;
  void printEdges(ParentNode node)
  {
    foreach(child; node.children)
      child.visit!((ParentNode childNode)
                   {
                     string title = "";
                     if ("title" in node.parameters)
                       title = node.parameters["title"];
                     string childTitle = "";
                     if ("title" in childNode.parameters)
                       childTitle = childNode.parameters["title"];
                     file.writeln('"', node.name, " ", title, '"', " -> ", '"', childNode.name, " ", childTitle, "\";");
                     printEdges(childNode);
                   },
                   (string line)
                   {
                   });
  }

  file.writeln("digraph {");
  printEdges(rootNode);
  file.writeln("}");
}

ParentNode parseTree(string source)
{

  import std.algorithm: map, each;
  import std.conv: to;
  import std.string: lineSplitter;
  ParentNode rootNode = new ParentNode();
  with(rootNode)
    {
      name = "root";
      children = [];
      parent = null;
    }
  parentNodes.insertFront(rootNode);
  source
    .lineSplitter
    .map!parse
    .each!process;

  return rootNode;
}
