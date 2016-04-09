module RethinkDB

import JSON

type RethinkDBConnection
  socket :: Base.TCPSocket
end

function connect(server::AbstractString = "localhost", port::Int = 28015)
  RethinkDBConnection(Base.connect(server, port))
end

function handshake(conn::RethinkDBConnection)
  # Version.V0_4
  version = UInt32(0x400c2d20)

  # Key Size
  key_size = UInt32(0)

  # Protocol.JSON
  protocol = UInt32(0x7e6970c7)

  handshake = pack_command([version, key_size, protocol])
  write(conn.socket, handshake)
  is_valid_handshake(conn)
end

function is_valid_handshake(conn::RethinkDBConnection)
  readstring(conn.socket) == "SUCCESS"
end

function readstring(sock::TCPSocket, msg = "")
  c = read(sock, UInt8)
  s = convert(Char, c)
  msg = string(msg, s)
  if (s == '\0')
    return chop(msg)
  else
    readstring(sock, msg)
  end
end

function pack_command(args...)
  o = Base.IOBuffer()
  for enc_val in args
    write(o, enc_val)
  end
  o.data
end

function disconnect(conn::RethinkDBConnection)
  close(conn.socket)
end

macro operate_on_zero_args(op_code::Int, name::Symbol)
  quote
    function $(esc(name))()
      [ $(op_code)  ]
    end
  end
end

macro operate_on_single_arg(op_code::Int, name::Symbol)
  quote
    function $(esc(name))(n)
      [ $(op_code), Array[[n]] ]
    end
  end
end

@operate_on_single_arg(57, db_create)
@operate_on_single_arg(58, db_drop)
@operate_on_zero_args(59, db_list)

function exec(conn::RethinkDBConnection, q)
  j = JSON.json([1, q])
  send_command(conn, j)
end

function token()
  t = Array{UInt64}(1)
  t[1] = object_id(t)
  return t[1]
end

function send_command(conn::RethinkDBConnection, json)
  t = token()
  q = pack_command([ t, convert(UInt32, length(json)), json ])

  write(conn.socket, q)
  read_response(conn, t)
end

function read_response(conn::RethinkDBConnection, token)
  remote_token = read(conn.socket, UInt64)
  if remote_token != token
    return "Error"
  end

  len = read(conn.socket, UInt32)
  res = read(conn.socket, len)

  output = convert(UTF8String, res)
  JSON.parse(output)
end

function do_test()
  c = RethinkDB.connect()
  res = RethinkDB.handshake(c)
  res ? println("Connected") : println("Not connected")

  db_create("tester") |> d -> exec(c, d) |> println
  db_drop("tester") |> d -> exec(c, d) |> println
  db_list() |> d -> exec(c, d) |> println


  # db("dbname") |> table("tablename") |> get("keyname") |> run(c)

  RethinkDB.disconnect(c)
end

end