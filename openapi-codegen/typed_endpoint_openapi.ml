open! Base
module Diagnostic = Model.Diagnostic
module Config = Model.Config
module Source = Model.Source
module Generated_file = Model.Generated_file

let generate = Generator.generate
let generate_sources = Generator.generate_sources
