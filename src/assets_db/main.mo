import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Map "mo:base/HashMap";
import Hash "mo:base/Hash";
import Iter "mo:base/Iter";
import Text "mo:base/Text";
import List "mo:base/List";
import Debug "mo:base/Debug";
import HashMap "mo:base/HashMap";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Cycles "mo:base/ExperimentalCycles";
import Types "types";
import Time "mo:base/Time";
import Error "mo:base/Error";

actor Asset_Management {
  

  public query func greet() : async () {
    Debug.print("Hello from Assets Canister with id " # Principal.toText(Principal.fromActor(Asset_Management)));
  };

  // Chunking
  // Upload and download code was taken by dfinity's example project and was adapted to this project
  // https://github.com/carstenjacobsen/examples/tree/master/motoko/fileupload

  private var nextChunkID : Nat = 0;

  // hashmap of all the chunks uploaded to the backend canister
  // key: chunk ID
  // value: chunk
  private let chunks : HashMap.HashMap<Nat, Types.Chunk> = HashMap.HashMap<Nat, Types.Chunk>(
    0,
    Nat.equal,
    Hash.hash,
  );

  // hashmap of collection of chunks belonging to a file.
  // key: batch_name e.g. "nodeID/assets/fileName.png"
  // value: collection of chunks belonging together (type Asset)
  private let assets : HashMap.HashMap<Text, Types.Asset> = HashMap.HashMap<Text, Types.Asset>(
    0,
    Text.equal,
    Text.hash,
  );

  // puts the given chunk in the chunks hashmap together with the created chunkID. It then returns the chunkID as a record for frontend
  public func create_chunk(chunk : Types.Chunk) : async { chunk_id : Nat } {
 
    nextChunkID := nextChunkID + 1;
    chunks.put(nextChunkID, chunk);

    return { chunk_id = nextChunkID };
  };

  // This method is to collect the chunks content that belong together and saves it in the assets hashmap under the batch_name(file name)
  public func commit_batch({
    node_id : Nat;
    batch_name : Text;
    chunk_ids : [Nat];
    content_type : Text;
  }) : async () {

    Debug.print("Commiting batch from: " # Principal.toText(Principal.fromActor(Asset_Management)));

    let content_chunks = Buffer.Buffer<[Nat8]>(4); //mutable array

    for (chunk_id in chunk_ids.vals()) {
      let chunk : ?Types.Chunk = chunks.get(chunk_id);

      switch (chunk) {
        case (?{ content }) {
          content_chunks.add(content);
        };
        case null {};
      };
    };

    if (content_chunks.size() > 0) {
      var total_length = 0;

      for (chunk in content_chunks.vals()) total_length += chunk.size();
      let content_chunks_array = Buffer.toArray(content_chunks);

      // assets hashmap takes as a key "nodeId/assets/fileNameExample.png"
      assets.put(
        "/" # Nat.toText(node_id) # "/assets/" # batch_name,
        {
          content_type = content_type;
          encoding = {
            modified = Time.now();
            content_chunks = content_chunks_array;
            certified = false;
            total_length;
          };
        },
      );

    };

  // remove chunks from chunks mapping. All the necessery informations is inside the assets mapping
    for (chunk_id in chunk_ids.vals()) {
      chunks.delete(chunk_id);
    };


  };

    public query func http_request(
      request : Types.HttpRequest
    ) : async Types.HttpResponse {

      if (request.method == "GET") {
        Debug.print("incoming GET request");
        // let split : Iter.Iter<Text> = Text.split(request.url, #char '?');
        // let key : Text = Iter.toArray(split)[0]; //e.g. "/assets/fileName"

        let split : Iter.Iter<Text> = Text.split(request.url, #text ".io");
        let key : Text = Iter.toArray(split)[1]; //e.g. "/assets/fileName"

        // asset hashmap lookup
        let asset : ?Types.Asset = assets.get(key);

        switch (asset) {
          case (?{ content_type : Text; encoding : Types.AssetEncoding }) {
            return {
              body = encoding.content_chunks[0];
              headers = [
                ("Content-Type", content_type),
                ("accept-ranges", "bytes"),
                ("cache-control", "private, max-age=0"),
              ];
              status_code = 200;
              streaming_strategy = create_strategy(
                key,
                0,
                { content_type; encoding },
                encoding,
              );
            };
          };
          case null {};
        };
      };

      return {
        body = Blob.toArray(Text.encodeUtf8("Permission denied. Could not perform this operation"));
        headers = [];
        status_code = 403;
        streaming_strategy = null;
      };
    };

    private func create_strategy(
      key : Text,
      index : Nat,
      asset : Types.Asset,
      encoding : Types.AssetEncoding,
    ) : ?Types.StreamingStrategy {
      switch (create_token(key, index, encoding)) {
        case (null) { null };
        case (?token) {
          let self : Principal = Principal.fromActor(Asset_Management);
          let canisterId : Text = Principal.toText(self);
          let canister = actor (canisterId) : actor {
            http_request_streaming_callback : shared () -> async ();
          }; // create actor reference

          return ?#Callback({
            token;
            callback = canister.http_request_streaming_callback;

          });
        };
      };
    };

    public query func http_request_streaming_callback(
      callbackToken : Types.StreamingCallbackToken
    ) : async Types.StreamingCallbackHttpResponse {

      switch (assets.get(callbackToken.key)) {
        case (null) throw Error.reject("key not found: " # callbackToken.key);
        case (?asset) {
          return {
            token = create_token(
              callbackToken.key,
              callbackToken.index,
              asset.encoding,
            );
            body = asset.encoding.content_chunks[callbackToken.index];
          };
        };
      };
    };

    private func create_token(
      key : Text,
      chunk_index : Nat,
      encoding : Types.AssetEncoding,
    ) : ?Types.StreamingCallbackToken {
      if (chunk_index + 1 >= encoding.content_chunks.size()) {
        null;
      } else {
        ?{
          key;
          index = chunk_index + 1;
          content_encoding = "gzip";
        };
      };
    };

};
