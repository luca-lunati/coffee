import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Types "./types";
import Nat "mo:base/Nat";
import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";
import Iter "mo:base/Iter";
import Text "mo:base/Text";
import List "mo:base/List";
import Utils "utils";
import Debug "mo:base/Debug";
import Time "mo:base/Time";
import Blob "mo:base/Blob";
import Error "mo:base/Error";
import Buffer "mo:base/Buffer";
import DraftNode "draftNode";
import Bool "mo:base/Bool";
import Prim "mo:prim";
import Cycles "mo:base/ExperimentalCycles";

actor Main {

  // Management canister actor reference. Used for canister creation
  let IC : Types.Management = actor ("aaaaa-aa");

  // variable saving wasm module that is needed for canister creation
  private  var assetCanisterWasm : [Nat8] = [];

  // list of all asset canister ids
  stable var assetCanisterIds = List.nil<Principal>();
  // adding current asset canister id to list
  //Live version
  assetCanisterIds := List.push<Principal>(Principal.fromText("kwgtv-yiaaa-aaaak-ae5cq-cai"), assetCanisterIds);
  //Local Version
  //assetCanisterIds := List.push<Principal>(Principal.fromText("bkyz2-fmaaa-aaaaa-qaaaq-cai"), assetCanisterIds);

  //Learning: Cant return non-shared classes (aka mutable classes). Save mutable data to this actor instead of node?
  var allNodes = List.nil<Types.Node>(); // make stable

  var nodeId : Nat = 0; // make stable
  func natHash(n : Text) : Hash.Hash {
    Text.hash(n);
  };
  //Contains all registered suppliers
  var suppliers = HashMap.HashMap<Text, Text>(0, Text.equal, natHash);

  // Contains all the drafts of each Supplier. Mapping from Supplier Id to a List of all Drafts
  var supplierToDraftNodeID = HashMap.HashMap<Text, List.List<DraftNode.DraftNode>>(0, Text.equal, natHash);

  //Returns greeting to logged in user
  public query (message) func greet() : async Text {
    let id = Principal.toText(message.caller);

    switch (suppliers.get(id)) {
      case null {
        return "Logged in with ID: " # id;
      };
      case (?supplier) {
        return "Logged in as: " # supplier # "\n Logged in with ID: " # id;
      };
    };

  };

  public query func wasm_is_empty() : async (Bool) {
    return  assetCanisterWasm == [];
  };

  public query func check_node_exists(id : Nat) : async (Bool) {
    Utils.node_exists(id, allNodes);
  };

  public query (message) func is_supplier_logged_in() : async (Bool) {
    Utils.is_supplier_logged_in(Principal.toText(message.caller), suppliers);
  };

  public query (message) func can_add_new_supplier() : async Bool {
    Utils.can_add_new_supplier(Principal.toText(message.caller), suppliers);
  };

  private func remove_draft(id : Nat, caller : Text) {
    let drafts = supplierToDraftNodeID.get(caller);
    switch (drafts) {
      case null {};
      case (?drafts) {
        let newList = List.filter<DraftNode.DraftNode>(drafts, func n { not (n.id == id) });
        supplierToDraftNodeID.put(caller, newList);
      };
    };

  };

  //Returns ID of last created node
  public shared func get_current_node_id() : async Nat {
    nodeId;
  };
  //Creates a New node with n child nodes. Child nodes are given as a list of IDs in previousnodes.
  //CurrentOwner needs to be the same as "nextOwner" in the given childNodes to point to them.
  //previousNodes: Array of all child nodes. If the first elementdfx is "0", the list is assumed to be empty.
  public shared (message) func create_leaf_node(draftId : Nat) : async (Text, Bool) {
    let caller = Principal.toText(message.caller);
    let draft = get_draft_as_object(draftId, caller);
    let owner = draft.owner;
    let username = suppliers.get(draft.owner.userId);
    let usernameNextOwner = suppliers.get(draft.nextOwner.userId);

    //Check if  next owner is null
    switch (usernameNextOwner) {
      case null { return ("Error: Next owner not found.", false) };
      case (?usernameNextOwner) {
        //Check if  current owner is null
        switch (username) {
          case null { return ("Error: Logged in Account not found.", false) };
          case (?username) {
            if (draft.previousNodesIDs[0] == 0) {
              let newNode = create_node(draft.id, List.nil(), draft.title, draft.owner, draft.nextOwner, draft.labelToText, draft.assetKeys);
              allNodes := List.push<Types.Node>(newNode, allNodes);
              remove_draft(draft.id, caller);
              ("Finalized node with ID: " #Nat.toText(draft.id), true);
            } else {
              // Map given Ids (previousNodes) to actual nodes, if they exist, they are added to childNodes

              var result = count_and_collect_valid_children(draft);

              //Check if all nodes were found
              if (result.0) {
                //Create the new node with a list of child nodes and other metadata
                let newNode = create_node(draft.id, result.1, draft.title, draft.owner, draft.nextOwner, draft.labelToText, draft.assetKeys);
                allNodes := List.push<Types.Node>(newNode, allNodes);
                remove_draft(draft.id, caller);
                ("Finalized node with ID: " #Nat.toText(draft.id), true);
              } else {
                return ("Error: Some Child IDs were invalid or missing ownership.", false);
              };
            };
          };
        };
      };
    };

  };

  //Matches every child of a given draft to existing nodes.
  //Returns true if all are present and have the correct owner, else returns false and the incomplete list
  private func count_and_collect_valid_children(draft : DraftNode.DraftNode) : (Bool, List.List<Types.Node>) {
    //Counter to keep track of amount of added nodes
    var counter = 0;
    var childNodes = List.filter<Types.Node>(
      allNodes,
      func n {

        var containsNode = false;
        for (i in Array.vals(draft.previousNodesIDs)) {
          //Check if the node exists and if the currentOwner was defined as the nextOwner
          if (n.nodeId == i and n.nextOwner.userId == draft.owner.userId and n.nodeId <= nodeId) {
            // and n.nodeId!=nodeId+1
            containsNode := true;
            counter += 1;
          };
        };

        containsNode;
      },
    );
    if (draft.previousNodesIDs.size() == counter) {
      return (true, childNodes);
    };
    return (false, childNodes);
  };
  //Creates a new Node, increments nodeId BEFORE creating it.
  private func create_node(
    id : Nat,
    previousNodes : List.List<Types.Node>,
    title : Text,
    currentOwner : Types.Supplier,
    nextOwner : Types.Supplier,
    labelToText : [(Text, Text)],
    assetKeys : [(Text, Text)],
  ) : (Types.Node) {

    {
      nodeId = id;
      title = title;
      owner = { userId = currentOwner.userId; userName = currentOwner.userName };
      nextOwner = { userId = nextOwner.userId; userName = nextOwner.userName };
      texts = labelToText;
      previousNodes = previousNodes;
      assetKeys = assetKeys;
    };
  };

  public shared func getCurrentNodeId() : async Nat {
    nodeId;
  };
  // Creates a DraftNode object. It takes nodeId and the owner.
  // with the created DraftNode object, it is added to the supplierToDraftNodeID Hashmap
  // that maps the suppliers to their drafts
  public shared (message) func create_draft_node(title : Text) : async Text {
    nodeId += 1;

    let ownerId = Principal.toText(message.caller);
    assert not Principal.isAnonymous(message.caller);
    let ownerName = suppliers.get(ownerId);

    switch (ownerName) {
      case null {
        return "Error: You are not a supplier";
      };
      case (?ownerName) {

        let node = DraftNode.DraftNode(nodeId, { userName = ownerName; userId = ownerId }, title);
        let nodeListDrafts = supplierToDraftNodeID.get(ownerId);
        var tempList = List.nil<DraftNode.DraftNode>();

        switch (nodeListDrafts) {
          case null {

          };
          case (?nodeListDrafts) {
            tempList := nodeListDrafts;
          };
        };
        tempList := List.push<DraftNode.DraftNode>(node, tempList);
        supplierToDraftNodeID.put(ownerId, tempList);
        return "Draft with id: " #Nat.toText(nodeId) # " succesfully created";
      };
    };

  };

  //Returns nodes as Text
  public query func show_all_nodes() : async Text {
    Utils.nodeListToText(allNodes);
  };

  public query func show_all_nodes_test() : async List.List<Types.Node> {
    allNodes;
  };

  //Takes all params for a draft and creates it
  public shared (message) func save_draft(nodeId : Nat, title : Text, nextOwner : Types.Supplier, labelToText : [(Text, Text)], previousNodes : [Nat], assetKeys : [(Text, Text)]) : async (Text) {
    let caller = Principal.toText(message.caller);

    assert not Principal.isAnonymous(message.caller);
    assert not (suppliers.get(caller) == null);

    let draftTemp = Utils.get_draft_by_id(nodeId, caller, supplierToDraftNodeID);

    switch (draftTemp) {
      case null {
        return "no draft node found under given ID";
      };
      case (?draftTemp) {
        draftTemp.title := title;
        draftTemp.nextOwner := nextOwner;
        draftTemp.labelToText := labelToText;
        draftTemp.previousNodesIDs := previousNodes;
        draftTemp.assetKeys := assetKeys;
        return " Draft successfully saved";
      };
    };

  };

  //recursively returns all edges from a tree
  private func get_edges(nodeId : Nat) : ([Types.Edge]) {

    var output = [{ start = ""; end = "" }];
    var node = Utils.get_node_by_id(nodeId, allNodes);
    switch (node) {
      case null { output := [] };
      case (?node) {
        List.iterate<Types.Node>(
          node.previousNodes,
          func n {
            let appendix = [{
              start = Nat.toText(n.nodeId);
              end = Nat.toText(nodeId);
            }];
            if (output[0].start == "") {
              output := appendix;
            } else {
              output := Array.append<Types.Edge>(output, appendix);
            };
            let childNodes = n.previousNodes;
            switch (childNodes) {
              case (null) {};
              case (?nchildNodes) {
                output := Array.append<Types.Edge>(output, get_edges(n.nodeId));
              };
            };
          },
        );
      };
    };
    output;
  };
  //Used to keep track of position of node on Y axis
  var levelY = 0;
  //recursively returns all edges from a tree
  private func get_simple_node_tree(nodeId : Nat, levelX : Nat) : ([Types.SimpleNode]) {

    var output = [{ id = ""; title = ""; levelX = 0; levelY = 0 }];
    var node = Utils.get_node_by_id(nodeId, allNodes);
    switch (node) {
      case null { output := [] };
      case (?node) {

        List.iterate<Types.Node>(
          node.previousNodes,
          func n {
            let appendix = [{
              id = Nat.toText(n.nodeId);
              title = n.title;
              levelX = levelX;
              levelY = levelY;
            }];
            if (output[0].id == "") {
              output := appendix;
            } else {
              output := Array.append<Types.SimpleNode>(output, appendix);
            };
            levelY := levelY +1;
            let childNodes = n.previousNodes;
            switch (childNodes) {
              case (null) {};
              case (?nchildNodes) {
                output := Array.append<Types.SimpleNode>(output, get_simple_node_tree(n.nodeId, levelX +1));
              };
            };
          },
        );
      };
    };
    output;
  };

  //Returns edges in format needed for UI
  public query func get_all_edges(nodeId : Nat) : async ([Types.Edge]) {
    get_edges(nodeId);
  };

  //Returns node in format needed for UI
  public query func get_all_simple_node_tree(nodeId : Nat) : async ([Types.SimpleNode]) {
    var node = Utils.get_node_by_id(nodeId, allNodes);
    switch (node) {
      case null { [] };
      case (?node) {
        Array.append<Types.SimpleNode>([{ id = Nat.toText(node.nodeId); title = node.title; levelX = 0; levelY = 0 }], get_simple_node_tree(nodeId, 1));
      };
    };
  };

  // Adds a new Supplier with to suppliers map with key = internet identity value = username
  // Only suppliers can add new suppliers. Exception for the first supplier which can be added by anyone to prevent bootstrap problem.
  public shared (message) func add_supplier(supplier : Types.Supplier) : async Text {
    let caller = Principal.toText(message.caller);

    // Exceptions for the first entry
    // Suppliers can only be added  by authorized users. Existing IDs may not be overwritten

    if ((suppliers.size() == 0 or suppliers.get(caller) != null) and suppliers.get(supplier.userId) == null) {
      suppliers.put(supplier.userId, supplier.userName);
      return "supplier added with\nID: " #supplier.userId # "\nName: " #supplier.userName;
    };

    return "Error: Request denied. Caller " #caller # " is not a supplier";
  };

  // Saves sent wasm module to 'assetCanisterWasm' variable that is sent via chunking
  public func save_wasm_module(blob : [Nat8]) : async ({ size : Nat }) {

    assetCanisterWasm := Array.append<Nat8>(assetCanisterWasm, blob);

    return { size = assetCanisterWasm.size() };
  };

  // Returns available asset canister for upload
  // If the current asset canister doesnt have enough memory, a new one is created
  public func get_available_asset_canister(fileSize : Nat) : async Text {

    if ((await has_enough_memory(fileSize))) {
      let currentAssetCanister = List.get<Principal>(assetCanisterIds, 0);
      switch (currentAssetCanister) {
        case (null) {
          throw Error.reject(" no asset canister available");
        };
        case (?currentAssetCanister) {
          return Principal.toText(currentAssetCanister);
        };
      };

    } else {
      return await create_canister(); // return newly created canister id

    };

  };

  // returns boolean if given file has enough space in the current asset canister
  private func has_enough_memory(fileSize : Nat) : async Bool {

    return (fileSize + (await get_used_memory())) < 4_186_000_000; // (ca. 3.9 GB)
  };

  // Makes a call to Management Canister and returns the current memory used
  // for the current asset canister
  private func get_used_memory() : async Nat {

    let currentAssetCanister = List.get<Principal>(assetCanisterIds, 0); // get newest asset canister id

    switch (currentAssetCanister) {
      case (null) {
        throw Error.reject(" no asset canister available");
      };
      case (?currentAssetCanister) {
        let status = await IC.canister_status({
          canister_id = currentAssetCanister;
        });
        return status.memory_size;
      };
    };

  };

  // Creates a new asset canister by sending a request to the Management canister.
  // The wasm code is installed in the newly created canister
  private func create_canister() : async (Text) {

    let settings_ : Types.CanisterSettings = {
      controllers = ?[Principal.fromActor(Main)];
      compute_allocation = null;
      memory_allocation = null;
      freezing_threshold = null;
    };

    Cycles.add(1000_000_000_000); 
    let cid = await IC.create_canister({ settings = settings_ });
    assetCanisterIds := List.push<Principal>(cid.canister_id, assetCanisterIds);
    let status = await IC.canister_status(cid);
    Debug.print("canister " #Principal.toText(cid.canister_id) # " has " # Nat.toText(status.cycles) # " cycles and " # Nat.toText(status.memory_size) # " bytes");

    await IC.install_code({
      mode = #install;
      canister_id = cid.canister_id;
      wasm_module = Blob.fromArray(assetCanisterWasm);
      arg = Blob.fromArray([]);
    });

    return Principal.toText(cid.canister_id);

  };

  //Returns all information of a node excluding id/childnodes
  //Values are all empty if node does not exist
  public query func get_node_by_id(id : Nat) : async (Text, Types.Supplier, Types.Supplier, [(Text, Text)], [(Text, Text)]) {
    let node = Utils.get_node_by_id(id, allNodes);
    switch (node) {
      case null {
        ("", { userName = ""; userId = "" }, { userName = ""; userId = "" }, [("", "")], [("", "")]);
      };
      case (?node) {
        return (node.title, node.owner, node.nextOwner, node.texts, node.assetKeys);
      };
    };
  };

  //Returns all drafts belonging to the caller
  public query (message) func get_drafts_by_supplier() : async [(Nat, Text)] {
    let caller = Principal.toText(message.caller);
    var draftList = supplierToDraftNodeID.get(caller);
    let listOfDraft = Buffer.Buffer<(Nat, Text)>(1);
    switch (draftList) {
      case null {};
      case (?draftList) {
        List.iterate<DraftNode.DraftNode>(draftList, func d { listOfDraft.add((d.id, d.title)) });
      };
    };
    return Buffer.toArray(listOfDraft);
  };

  //Returns draft with given id. If the id is not found, an empty draft is returned.
  public query (message) func get_draft_by_id(id : Nat) : async (Nat, Text, Types.Supplier, [(Text, Text)], [Nat], [(Text, Text)]) {
    let caller = Principal.toText(message.caller);

    let emptyDraft = (0, "", { userName = ""; userId = "" }, [("", "")], [0], [("", "")]);

    let draftTemp = Utils.get_draft_by_id(id, caller, supplierToDraftNodeID);

    switch (draftTemp) {
      case null {
        return emptyDraft;
      };
      case (?draftTemp) {
        return (draftTemp.id, draftTemp.title, draftTemp.nextOwner, draftTemp.labelToText, draftTemp.previousNodesIDs, draftTemp.assetKeys);
      };
    };
  };

  // Searches and returns a draft as a new DraftNode object
  private func get_draft_as_object(id : Nat, caller : Text) : DraftNode.DraftNode {

    let emptyDraft = DraftNode.DraftNode(0, { userName = ""; userId = "" }, "");

    let draftTemp = Utils.get_draft_by_id(id, caller, supplierToDraftNodeID);

    switch (draftTemp) {
      case null {
        return emptyDraft;
      };
      case (?draftTemp) {
        return draftTemp;
      };
    };
  };


  public query func get_suppliers() : async [Text] {
    Iter.toArray(suppliers.vals());
  };

  public query (message) func get_caller() : async Text {
    return Principal.toText(message.caller);
  };
  // Create supply-chain for user data put in, returns last ID of node
  public shared func a_set_up_test_data(id : Text, userName : Text) : async (Nat) {
    nodeId := nodeId +1;
    let farmer1 = create_node(nodeId, List.nil(), "Farmer", { userId = id; userName = userName }, { userId = id; userName = userName }, [], []);
    nodeId := nodeId +1;
    let farmer2 = create_node(nodeId, List.nil(), "Farmer", { userId = id; userName = userName }, { userId = id; userName = userName }, [], []);
    nodeId := nodeId +1;
    let exporter = create_node(nodeId, List.nil(), "Exporter", { userId = id; userName = userName }, { userId = id; userName = userName }, [], []);
    nodeId := nodeId +1;
    let cooperative = create_node(nodeId, List.nil(), "Cooperative", { userId = id; userName = userName }, { userId = id; userName = userName }, [], []);
    nodeId := nodeId +1;
    let cooperative2 = create_node(nodeId, List.nil(), "Cooperative", { userId = id; userName = userName }, { userId = id; userName = userName }, [], []);
    allNodes := List.push<Types.Node>(farmer1, allNodes);
    allNodes := List.push<Types.Node>(farmer2, allNodes);
    allNodes := List.push<Types.Node>(exporter, allNodes);
    allNodes := List.push<Types.Node>(cooperative, allNodes);
    allNodes := List.push<Types.Node>(cooperative2, allNodes);
    var courierChildren = List.nil<Types.Node>();
    courierChildren := List.push<Types.Node>(farmer1, courierChildren);
    courierChildren := List.push<Types.Node>(cooperative, courierChildren);
    let courier = create_node(nodeId, courierChildren, "Courier Service", { userId = id; userName = userName }, { userId = id; userName = userName }, [], []);
    nodeId := nodeId +1;
    allNodes := List.push<Types.Node>(courier, allNodes);

    var marketChildren = List.nil<Types.Node>();
    marketChildren := List.push<Types.Node>(farmer2, marketChildren);
    marketChildren := List.push<Types.Node>(exporter, marketChildren);
    marketChildren := List.push<Types.Node>(cooperative2, marketChildren);
    let marketplace = create_node(nodeId, marketChildren, "Marketplace", { userId = id; userName = userName }, { userId = id; userName = userName }, [], []);
    nodeId := nodeId +1;
    allNodes := List.push<Types.Node>(marketplace, allNodes);

    var shopChildren = List.nil<Types.Node>();
    shopChildren := List.push<Types.Node>(courier, shopChildren);
    shopChildren := List.push<Types.Node>(marketplace, shopChildren);
    let shop = create_node(nodeId, shopChildren, "Speciality Coffee Shop", { userId = id; userName = userName }, { userId = id; userName = userName }, [], []);
    allNodes := List.push<Types.Node>(shop, allNodes);
    return nodeId;
  };
};
