var util = require('util');
var fs   = require('fs');

var RubyParser = require('./parse.js').RubyParser;
RubyParser.prototype.print = util.print;

var parser = new RubyParser();

var text;
if (process.argv[2] !== undefined)
  text = process.argv[2];
else
  text = fs.readFileSync('/dev/stdin').toString();

var json = parser.toJSON(text);

util.print(json + '\n');

process.exit(json ? 0 : 1);

