module liderate.treelan.parser;

version(none)
{

  import std.stdio;

  const string testSource = import("example.liderate");
  class Portion
  {
    bool isModule;
    string name;
    struct Ref
    {
      string portionName;
    }
    import std.variant: Algebraic;
    alias RefOrText = Algebraic!(Ref, string);
    RefOrText[] content;
    string text;
  }

  import liderate.treelan.parser;

  Portion[string] portionsByName;
  Portion[string] modulesByName;
  void extractPortions(ParentNode root)
  {
    void dfs(string currentPrefix, ParentNode parent)
    {
      import std.conv: text;
      import std.variant: visit;
      switch(parent.name)
        {
        case "section":
          currentPrefix ~= text(parent.parameters["id"], "/");
          foreach(child; parent.children)
            child.visit!((ParentNode node)
                         {
                           dfs(currentPrefix, node);
                         },
                         (string line)
                         {
                         });
          break;
        case "define":
          if ("id" in parent.parameters)
            {
              Portion portion = new Portion();
              with (portion)
                {
                  isModule = false;
                  name = currentPrefix ~ parent.parameters["id"];
                  content = null;
                  portion.text = null;
                }
              portionsByName[portion.name] = portion;
            }
          else if ("module" in parent.parameters)
            {
              Portion portion = new Portion();
              with (portion)
                {
                  isModule = true;
                  name = parent.parameters["module"];
                  content = null;
                  portion.text = null;
                }
              modulesByName[portion.name] = portion;
            }
          else
            assert(0, "A define without id or module parameter");
          break;
        case "portion":
          Portion portion;
          if ("id" in parent.parameters)
            {
              string id = parent.parameters["id"];
              string portionName;
              assert(id.length > 0);
              if (id[0] == '/')
                {
                  portionName = id;
                }
              else
                {
                  portionName = currentPrefix ~ id;
                }
              portion = portionsByName[portionName];
            }
          else if ("module" in parent.parameters)
            {
              portion = modulesByName[parent.parameters["module"]];
            }
          else
            assert(0, "A portion without module or id parameter");
          foreach(child; parent.children)
            {
              child.visit!((ParentNode node)
                           {
                             assert(node.name == "ref");
                             string id = node.parameters["id"];
                             assert(id.length > 0);
                             if (id[0] == '/')
                               {
                                 portion.content ~= Portion.RefOrText(Portion.Ref(id));
                               }
                             else
                               {
                                 portion.content ~= Portion.RefOrText(Portion.Ref(currentPrefix ~ id));
                               }
                           },
                           (string line)
                           {
                             portion.content ~= Portion.RefOrText(line);
                           });
            }
          break;
        case "root":
          foreach(child; parent.children)
            {
              child.visit!((ParentNode node)
                           {
                             dfs("/", node);
                           },
                           (string line){});
            }
          break;
        default:
          import std.conv: text;
          assert(0, text("Unknown node type ", parent.name));
        }
    }
    dfs("/", root);
  }

  enum ResolvingState
    {
      none,
      resolving,
      resolved,
    };
  ResolvingState[Portion] resolvingState;
  class ReferenceCycle: Exception
  {
    this(string file = __FILE__, size_t line = __LINE__)
    {
      super("Cycle found in portion reference graph.", file, line);
    }
  }
  void resolveText(Portion portion)
  {
    resolvingState.require(portion, ResolvingState.none);
    assert(resolvingState[portion] == ResolvingState.none);
    resolvingState[portion] = ResolvingState.resolving;
    foreach(line; portion.content)
      {
        import std.variant: visit;
        line.visit!((Portion.Ref reference)
                    {
                      Portion referencedPortion = portionsByName[reference.portionName];
                      resolvingState.require(referencedPortion, ResolvingState.none);
                      final switch(resolvingState[referencedPortion])
                        {
                        case ResolvingState.none:
                          resolveText(referencedPortion);
                          assert(resolvingState[referencedPortion] == ResolvingState.resolved);
                          portion.text ~= "\n" ~ referencedPortion.text;
                          break;
                        case ResolvingState.resolving:
                          throw new ReferenceCycle();
                        case ResolvingState.resolved:
                          portion.text ~= "\n" ~ referencedPortion.text;
                          break;
                        }
                    },
                    (string literalLine)
                    {
                      portion.text ~= "\n" ~ literalLine;
                    });
      }
    resolvingState[portion] = ResolvingState.resolved;
  }
}

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
