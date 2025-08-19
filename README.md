# simple-hole-punch 
A simplified UDP hole punch server and client for Godot.

```
This UPD hole punching protocol minimizes communication from the server to help it function on free cloud instances.
The onus is on the client to resend any lost UDP messages, and so each handler can handle receiving duplicates.
It can be used to match several clients to one host, or to match two random clients together.

BASIC PROTOCOL

S = Server
A = Host
B = Client

Standard Registration:
A=>S    [HS]    host_session       Register with the matchmaking server as a host.  
S=>A    [HR]    _host_registered   Host has been registered and provided with session id

B=>S    [JS]    join_session       Register with the matchmaking server to join a specific session.
S=>B    [JR]    _join_registered   Client registered and provided with the host's local and remote key.
S=>A    [NJ]    _new_joiner        Host notiffied of new client and provided with the client's local and remote key.

Random Registration:
A=>S    [RS]    random_session    Register with the matchmaking server to either host or join a random session.
S=>A    [HR]    _host_registered  The server did not have an active random host, register them as a random host.

B=>S    [RS]    random_session    Register with the matchmaking server to either host or join a random session.
S=>B    [JR]    _join_registered  The server did have an active random host, register them as a random client.
S=>A    [NJ]    _new_joiner       Host notified of random match. The session is complete, close the session.

Peer to Peer Holepunching:
A=>B    [RD]    _peer_ready      A peer is ready to proceed. Take note of whether they use their local or remote key.
B=>A    [RD]    _peer_ready      A peer is ready to proceed. Take note of whether they use their local or remote key.
(these are repeated until the session is closed to keep the hole punched)

Session Complete:
A=>S    [CS]    close_session   The host is closing the session. Clean up their details from the list of sessions.
A=>B    [JH]    _join_host      The host is closing the session. Use the hole punched to connect to the host directly with a MultiplayerPeer.
B=>A    [JD]    _join_done      The client is trying to connect directly. When all clients are done, start hosting directly with a MultiplayerPeer.

CLIENT API

host_session(serv_key: String, alias: String)      Register with the matchmaking server as a host.  
join_session(id: String, alias: String)            Register with the matchmaking server to join a specific session.
random_session(serv_key: String, alias: String)    Register with the matchmaking server to either host or join a random session.
close_session()                                    The host is closing the session. Clean up their details from the list of sessions.
get_host()                                         Retreive the host details to attempt reconnection.

SIGNALS

signal start_server(port: int)                     Matches complete - time to start MultiplayerPeer server
signal start_client(ip: String, port: int, local_port: int)    Matches complete - time to start MultiplayerPeer client
signal start_session(key: String)                  Host registered and session ID assigned
signal new_name(name: String)                      A new peer is matched and ready
signal bad_session(key: String)                    The session ID does not exist
signal bad_server(key: String)                     The matchmaking server is unresponsive
signal start_random()                              Client matched in a random pair

```
