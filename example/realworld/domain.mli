open! Base

module Article : sig
  type t =
    { id : int
    ; title : string
    ; body : string
    ; author : string
    }
end

module New_article : sig
  type t =
    { title : string
    ; body : string
    }
end
