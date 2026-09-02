open! Base

module Article = struct
  type t =
    { id : int
    ; title : string
    ; body : string
    ; author : string
    }
end

module New_article = struct
  type t =
    { title : string
    ; body : string
    }
end
