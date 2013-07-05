require 'v8'
# require 'oj'

class ParserJS
  @@js = nil
  
  def load_parser
    return true if @@js
    
    @@js = V8::Context.new

    # for error logging and debugging
    @@js["print"] = lambda { |this, *msg| puts(msg.join(' ')) }
    @@js["write"] = lambda { |this, *msg| print(msg.join(' ')) }

    # allow module to export itself
    @@js["write"] = lambda { |this, *msg| print(msg.join(' ')) }
    @@js.eval("global = this;")

    @@js.load('/www/parser/parse.js')
    
  end

  def initialize
    load_parser
    
    @@js.eval <<-JS

      var lexer = new YYLexer();
      lexer.filename = '(source)';
  
      var parser = new YYParser(lexer);

      function to_plain (n)
      {
        if (!(n && n.type))
          return n;

        var ary = n.slice();
        ary.unshift(n.type);

        for (var i = 0, il = ary.length; i < il; i++)
          ary[i] = to_plain(ary[i]);

        return ary;
      }

      function declare (v)
      {
        parser.declareVar(v);
      }
      
      function give_me_json (ruby)
      {
        lexer.setText(ruby);
        var ok = parser.parse(ruby);
        return JSON.stringify(to_plain(parser.resulting_ast));
      }

    JS

    @give_me_json = @@js.eval("give_me_json")
    @declare      = @@js.eval("declare")
  end
  
  def parse source
    @give_me_json.call(source)
  end
  
  def declare var
    @declare.call(var)
  end
  
  def filename= fn
    @@js.eval(%{(function (fn) { lexer.filename = fn; })}).call(fn)
  end
end

# puts ParserJS.new.to_json("1+2")
