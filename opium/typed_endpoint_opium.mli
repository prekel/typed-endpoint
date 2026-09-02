include
  Typed_endpoint.Backend.S
  with type req = Opium.Std.Request.t
   and type resp = Opium.Std.Response.t
   and type 'a io = 'a Lwt.t
   and type app_builder = Opium.Std.App.t -> Opium.Std.App.t
