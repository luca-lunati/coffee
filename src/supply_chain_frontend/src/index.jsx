import { createActor, supply_chain_backend } from "../../declarations/supply_chain_backend";
import { createActor as createAssetActor, assets_db } from "../../declarations/assets_db";
import { AuthClient } from "@dfinity/auth-client"
import { HttpAgent } from "@dfinity/agent";
import * as React from 'react';
import { render } from 'react-dom';
import React from 'react';
import "./main.css"
import Flow from "./Flow";
import { MarkerType } from "reactflow";


class SupplyChain extends React.Component {

  constructor(props) {
    super(props);
    this.state = {
      actor: supply_chain_backend,
      asset_canister: assets_db,
      file: null,
      wasm: null,
      agent: null,
      //Live version 
      assets_canisterid: "kwgtv-yiaaa-aaaak-ae5cq-cai",
      //Local version
      //assets_canisterid: "bkyz2-fmaaa-aaaaa-qaaaq-cai",
      drafts: [{ id: '', title: '' }],
      currentDraft: {
        id: 0,
        title: '',
        nextOwner: { userName: '', userId: '' },
        labelToText: [{ label: '', text: '' }],
        previousNodesIDs: '',
        draftFile: [{ url: '', canisterId: '' }]
      },
      currentNode: {
        id: 0,
        title: '',
        owner: { userName: '', userId: '' },
        nextOwner: { userName: '', userId: '' },
        labelToText: [{ label: '', text: '' }],
        files: [{ url: '', canisterId: '' }]
      },
      allNodes: [{
        id: 0,
        title: '',
        owner: { userName: '', userId: '' },
        childNodes: [{ userId: '' }],
        nextOwner: { userName: '', userId: '' },
        labelToText: [{ label: '', text: '' }],
        files: [{ url: '', canisterId: '' }]
      }],
      edges: [],
      tree: []
    };


  }


  async wasmHandler(event) {
    this.state.wasm = event.target.files[0];


  }

  async createCanister() {
    await this.state.actor.create();
  }

  async installWasm() {
    const promises = [];


    const chunkSize_ = 700000;


    for (let start = 0; start < this.state.wasm.size; start += chunkSize_) {
      const chunk = this.state.wasm.slice(start, start + chunkSize_);


      promises.push(this.uploadWasm(
        chunk
      ));
    }

    await Promise.all(promises);


    document.getElementById("createCanister").style.display = "none";

  };

  async uploadWasm(chunk) {
    return await this.state.actor.save_wasm_module(
      [...new Uint8Array(await chunk.arrayBuffer())]
    );
  }



  handleAddField = () => {
    const { labelToText } = this.state.currentDraft;
    const newLabelToText = [...labelToText, { label: '', text: '' }];
    this.setState({
      currentDraft: {
        ...this.state.currentDraft,
        labelToText: newLabelToText
      }
    });
  };


  handleRemoveField = (index) => {
    const { labelToText } = this.state.currentDraft;
    const newLabelToText = [...labelToText];
    newLabelToText.splice(index, 1);
    this.setState({
      currentDraft: {
        ...this.state.currentDraft,
        labelToText: newLabelToText
      }
    });
  };

  handleFieldChange = (index, fieldName, event) => {
    const { labelToText } = this.state.currentDraft;
    const newLabelToText = [...labelToText];
    newLabelToText[index][fieldName] = event.target.value;
    this.setState({
      currentDraft: {
        ...this.state.currentDraft,
        labelToText: newLabelToText
      }
    });
  };

  handleNextOwnerChange = (event) => {
    const newNextOwner = event.target.value;
    this.setState({
      currentDraft: {
        ...this.state.currentDraft,
        nextOwner: {
          ...this.state.currentDraft.nextOwner,
          userId: newNextOwner
        }
      }
    });
  };

  handleTitleChange = (event) => {
    const newTitle = event.target.value;
    this.setState({
      currentDraft: {
        ...this.state.currentDraft,
        title: newTitle
      }
    });
  };

  handleChildNodesChange = (event) => {
    const newChildNodesS = event.target.value;
    let newChildNodes = newChildNodesS.split(',').map(function (item) {
      return parseInt(item, 10);
    });
    this.setState({
      currentDraft: {
        ...this.state.currentDraft,
        previousNodesIDs: newChildNodes

      }
    });
  };

  async getNodeById() {

    let idInput = document.getElementById("nodeId");
    let idValue = BigInt(idInput.value);

    let nodeExists = await this.state.actor.check_node_exists(idValue);


    if (nodeExists) {
      let node = await this.state.actor.get_node_by_id(idValue); // maybe cast in BigInt
      const { currentNode } = this.state;
      currentNode.id = idInput;
      currentNode.title = node[0];
      currentNode.owner = node[1];
      currentNode.nextOwner = node[2];
      currentNode.labelToText = node[3].map(([label, text]) => ({
        label,
        text
      }));
      currentNode.files = node[4].map(([url, canisterId]) => ({
        url,
        canisterId
      }));
      this.setState({ currentNode: currentNode });

      this.loadImage(currentNode.files, false);
    } else {
      alert("invalid node id");
    }



  }

  showNode() {

    const tmpNode = this.state.currentNode;

    if (tmpNode.id != 0) {
      return (
        <div><h1>{tmpNode.title}</h1>

          <label>Owner ID:  </label><label>{tmpNode.owner.userId}</label>
          <br></br>
          <label>Next Owner ID:  </label><label>{tmpNode.nextOwner.userId}</label>

          <div>

            {(tmpNode.labelToText || []).map((field, index) => (
              <div>
                <label>{field.label}:  </label>
                <label>{field.text}</label>
              </div>

            ))}

          </div>
          <h4>Files</h4>
          <section>
            <section id="nodeImage"></section>
          </section>
        </div>)
    }

  }


  async finalizeNode() {
    let response = await this.state.actor.create_leaf_node(this.state.currentDraft.id);

    alert(response[0]);
    if (response[1]) {
      this.state.currentDraft = {
        id: 0,
        title: '',
        nextOwner: { userName: '', userId: '' },
        labelToText: [{ label: '', text: '' }],
        previousNodesIDs: [0],
        draftFile: [{ url: '', canisterId: '' }]
      }
      this.getDraftBySupplier()
    }

  }

  async saveDraft() {

    if (this.state.file) {
      await this.upload();
    }

    const { currentDraft } = this.state;


    // Construct Arguments to send to backend canister
    const currentD = [
      BigInt(currentDraft.id),
      currentDraft.title,
      { userName: currentDraft.nextOwner.userName, userId: currentDraft.nextOwner.userId },
      currentDraft.labelToText.map(({ label, text }) => [label, text]),
      currentDraft.previousNodesIDs,
      currentDraft.draftFile.map(({ url, canisterId }) => [url, canisterId]),
    ];

    let response = await this.state.actor.save_draft(...currentD);
    this.state.file = null;
    alert(response);
    this.loadImage(currentDraft.draftFile, true)

  }

  async addSupplier() {
    let userName = document.getElementById("newSupplierName");
    let userID = document.getElementById("newSupplierID");
    const supplier = {
      userName: userName.value,
      userId: userID.value,

    }
    let response = await this.state.actor.add_supplier(supplier);

    userName.value = "";
    userID.value = "";
    alert(response)
    this.showCreateDraft()

    const greeting = await this.state.actor.greet();
    document.getElementById("greeting").innerText = greeting;


  }

  async createNode() {
    const caller = await this.state.actor.get_caller();

    const title = this.state.currentDraft;
    const children = children.value;
    const nextOwner = nextOwnerID.value;

    let response = "";
    if (title.length > 0) {
      //Check if there are any child nodes. If not, the node is a "rootnode", which is a node without children
      if (children.length == 0) {
        response += await this.state.actor.create_leaf_node([0], title, caller, nextOwner);
      } else {
        //Split child node IDs by ","
        let numbers = children.split(',').map(function (item) {
          return parseInt(item, 10);
        });
        response += await this.state.actor.create_leaf_node(numbers, title, caller, nextOwner);
      }

      if (caller === "2vxsx-fae") {
        response = "Node was not created. Login to a supplier account to create nodes."
      }
      alert(response)
    }
  }

  async createDraftNode() {
    const caller = await this.state.actor.get_caller();
    let response = "";
    if (caller === "2vxsx-fae") {
      response = "Node was not created. Login to a supplier account to create nodes."
    } else {

      let title = document.getElementById("newNodeTitle");

      const tValue = title.value;

      title.value = "";


      if (tValue.length > 0) {
        //Check if there are any child nodes. If not, the node is a "rootnode", which is a node without children

        response = await this.state.actor.create_draft_node(tValue);
        alert(response)
        this.getDraftBySupplier()

      }
    }


  }

  async getDraftBySupplier() {
    let isSupplier = await this.state.actor.is_supplier_logged_in();

    let myElement = document.getElementById("draftsList");
    if (isSupplier) {

      let result = await this.state.actor.get_drafts_by_supplier();
      myElement.style.display = "block"; // Show the element

      let tempDrafts = [];
      result.forEach((d) => {
        tempDrafts = [...tempDrafts, { id: Number(d[0]), title: d[1] }]

      });
      this.setState({ drafts: tempDrafts });

    } else {
      myElement.style.display = "none";
    }


  }
  async login() {


    let authClient = await AuthClient.create();


    await new Promise((resolve) => {
      authClient.login({
        identityProvider: process.env.II_URL,
        onSuccess: resolve,
      });
    });

    // At this point we're authenticated, and we can get the identity from the auth client:
    const identity = authClient.getIdentity();

    // Using the identity obtained from the auth client, we can create an agent to interact with the IC.
    this.state.agent = new HttpAgent({ identity });
    const agent = this.state.agent;
    // Using the interface description of our webapp, we create an actor that we use to call the service methods. We override the global actor, such that the other button handler will automatically use the new actor with the Internet Identity provided delegation.
    this.state.actor = createActor(process.env.SUPPLY_CHAIN_BACKEND_CANISTER_ID, {
      agent,
    });


    const wasmIsEmpty = await this.state.actor.wasm_is_empty();
    if (wasmIsEmpty) {
      document.getElementById("createCanister").style.display = "block";
    }

    const greeting = await this.state.actor.greet();
    document.getElementById("greeting").innerText = greeting;

    this.getDraftBySupplier();
    this.showCreateDraft();
    this.showAddSupplier();
    return false;

  }


  async setCurrentDraft(id) {
    let draft = await this.state.actor.get_draft_by_id(id);
    const { currentDraft } = this.state;
    currentDraft.id = Number(draft[0]);
    currentDraft.title = draft[1];
    currentDraft.nextOwner = draft[2];
    currentDraft.labelToText = draft[3].map(([label, text]) => ({
      label,
      text
    }));
    currentDraft.previousNodesIDs = draft[4];
    currentDraft.draftFile = draft[5].map(([url, canisterId]) => ({
      url,
      canisterId
    }));
    this.setState({ currentDraft: currentDraft });

    // remove images and file from the last current draft
    const section = document.querySelector('#draftImage');
    while (section.firstChild) {
      section.removeChild(section.firstChild);
    }

    this.loadImage(currentDraft.draftFile, true);

  }



  async getNodes() {
    let all = await this.state.actor.show_all_nodes_test();
    all = all.flat(Infinity);

    if (all.length > 0) {
      const formattedNodes = all.map((node) => ({
        id: Number(node.nodeId),
        title: node.title || "",
        owner: {
          userName: node.owner?.userName || "",
          userId: node.owner?.userId || "",
        },
        nextOwner: {
          userName: node.nextOwner?.userName || "",
          userId: node.nextOwner?.userId || "",
        },
        childNodes: (node.previousNodes || []).map((userId) => ({
          userId
        })),
        labelToText: (node.texts || []).map(([label, text]) => ({
          label,
          text
        })),
        files: (node.assetKey || []).map(([url, canisterId]) => ({
          url,
          canisterId
        })),
      }));

      this.setState({ allNodes: formattedNodes });
      this.showNodes()
    } else {
      alert("No nodes found");
    }
  }

  showNodes() {
    if (this.state.allNodes[0].id != 0) {
      return (
        <div className="node-list">
          {this.state.allNodes.map((node, index) => (
            <div className="node-box" key={index}>
              <p>Title: {node.title}</p>
              <p>Owner username: {node.owner.userName}</p>
            </div>
          ))}
        </div>
      )
    }

  }

  async renderNode(node) {
    const { id, title, childNodes } = node;
    return (
      <div key={id} className="node">
        <p>{title}</p>
        <div className="child-nodes">
          {childNodes && childNodes.length > 0
            ? childNodes.map((childNode) => this.renderNode(childNode))
            : null}
        </div>
      </div>
    );
  }



  async getSuppliers() {
    let all = await this.state.actor.get_suppliers();
    document.getElementById("suppliers").innerHTML = all;

  }
  //converts nodes and edges to format needed for UI
  async getEdgesAndSimpleNodes(parentId) {
    let tmpEdges = await this.state.actor.get_all_edges(parentId);
    tmpEdges = tmpEdges.flat(Infinity);
    const formattedEdges = tmpEdges.map((e) => ({
      id: e.start + "-" + e.end,
      source: e.start,
      target: e.end,
      markerEnd: {
        type: MarkerType.ArrowClosed
      }
    }));
    this.setState({ edges: formattedEdges });

    let tmpEtree = await this.state.actor.get_all_simple_node_tree(parentId);
    tmpEtree = tmpEtree.flat(Infinity);
    const formattedTree = tmpEtree.map((t) => ({
      id: t.id,
      data: { label: "#" + t.id + " " + t.title },
      position: { x: Number(t.levelX) * 300, y: Number(t.levelY) * 50 }
    }));
    this.setState({ tree: formattedTree });
  }
  async getChildNodes() {
    let tree = document.getElementById("parentId");
    const tValue = parseInt(tree.value, 10);
    if (tValue >= 0) {
      this.getEdgesAndSimpleNodes(tValue);
    }
  }

  async prepareAssetCanister(fileSize) {
    let availableAssetCanister = await this.getAvailableAssetCanister(fileSize);

    if (availableAssetCanister != this.state.assets_canisterid) {
      this.state.assets_canisterid = availableAssetCanister
      await this.createActorRef();
    }


    return availableAssetCanister;
  }

  async getAvailableAssetCanister(fileSize) {

    let canisterID = await this.state.actor.get_available_asset_canister(fileSize);
    return canisterID;

  }

  async createActorRef() {
    const agent = this.state.agent; // agent will be created when login through ii is successful

    this.state.asset_canister = createAssetActor(this.state.assets_canisterid, {
      agent,
    });

    await this.state.asset_canister.greet();
  };




  // Upload and download code was taken by dfinity's example project and was adapted to this project
  // https://github.com/carstenjacobsen/examples/tree/master/motoko/fileupload
  async handleFileSelection(event) {
    this.state.file = event.target.files[0];

  }



  async upload() {

    if (!this.state.file) {
      alert('No file selected');
      return;
    }

    let availableAssetCanister = await this.prepareAssetCanister(this.state.file.size);



    const { currentDraft } = this.state;

    let newName = this.state.file.name.replace(/\s/g, ""); // remove whitespaces so no error occurs in the GET method URL
    this.state.file = new File([this.state.file], newName, { type: this.state.file.type });

    const batch_name = this.state.file.name;
    const promises = [];
    const chunkSize = 1500000; //Messages to canisters cannot be larger than 2MB. The chunks are of size 1.5MB

    for (let start = 0; start < this.state.file.size; start += chunkSize) {

      // Create a chunk from file in size defined in chunkSize
      const chunk = this.state.file.slice(start, start + chunkSize); // returns a Blob obj

      // Fill array with the uploadChunkt function. The array be executed later
      // "uploadChunk" takees the batch_name(file name) and the chunk
      promises.push(this.uploadChunk({
        batch_name,
        chunk
      }));
    }

    // Executes the "uploadChunk" defined in the promises array. Returns the chunkIDs created in the backend
    const chunkIds = await Promise.all(promises);

    const node_id = BigInt(currentDraft.id)

    //Finish upload by commiting file batch to be saved in backend canister with the current node ID
    await this.state.asset_canister.commit_batch({
      node_id,
      batch_name,
      chunk_ids: chunkIds.map(({ chunk_id }) => chunk_id),
      content_type: this.state.file.type
    })

    const assetKey = [
      ...currentDraft.draftFile,
      { url: "/" + currentDraft.id + "/assets/" + batch_name, canisterId: availableAssetCanister }
    ];
    this.setState({
      currentDraft: {
        ...this.state.currentDraft,
        draftFile: assetKey
      }
    });


    // Once the files has been saved in the backend canister it can be loaded to be seen on the frontend
    this.loadImage(currentDraft.draftFile, true);
  }

  // Takes a record of batch_name and chunk
  // calls the backend canister method "create_chunk"
  //converts chunk of type Blob into a Uint8Array to send it to backend canister. Motoko reads it as [Nat8]
  async uploadChunk({ batch_name, chunk }) {
    return this.state.asset_canister.create_chunk({
      batch_name,
      content: [...new Uint8Array(await chunk.arrayBuffer())]
    });
  }



  loadImage(files, isDraft) {
    if (!files) {
      return;
    }

    const section = isDraft ? document.querySelector('#draftImage') : document.querySelector('#nodeImage');

    while (section.firstChild) {
      section.removeChild(section.firstChild);
    }

    // Create a document fragment to hold the image tags
    const fragment = document.createDocumentFragment();

    // Iterate over the image sources and create image tags
    files.forEach((file) => {
      const { url, canisterId } = file;
      const fileExtension = url.split('.').pop().toLowerCase();

      if (fileExtension === 'pdf') {
        // Handle PDF files
        const embed = document.createElement('embed');
        embed.width = 600;
        embed.height = 400;
        embed.src = `http://${canisterId}.raw.icp0.io?${url}`;
       // embed.src = `http://localhost:4943${url}?canisterId=${canisterId}`;
        fragment.appendChild(embed);
      } else {
        // Handle image files
        const img = document.createElement('img');
        img.width = 300;
        img.height = 200;
        img.src = `http://${canisterId}.raw.icp0.io?${url}`;
        //img.src = `http://localhost:4943${url}?canisterId=${canisterId}`;
        fragment.appendChild(img);
      }
    });


    // Append the fragment to the section element
    section?.appendChild(fragment);
  }


  showDraft() {

    const tmpDraft = this.state.currentDraft;

    if (tmpDraft.id != 0) {
      return (<div><h1>Complete "{tmpDraft.title}" Draft</h1>
        <div>
          <label>Title:</label>
          <input value={tmpDraft.title} onChange={(event) => this.handleTitleChange(event)}></input>
        </div>
        <table>
          <tbody>
            <tr>
              <td>Next Owner ID:</td><td><input value={tmpDraft.nextOwner.userId} onChange={(event) => this.handleNextOwnerChange(event)}></input></td>
              <td>Child nodes:</td><td><input type="text" value={tmpDraft.previousNodesIDs} onChange={(event) => this.handleChildNodesChange(event)}></input></td>
            </tr>
          </tbody>
        </table>
        <div>

          {(tmpDraft.labelToText || []).map((field, index) => (
            <div key={index}>
              <input
                type="text"
                value={field.label}
                onChange={(event) => this.handleFieldChange(index, 'label', event)}
              />
              <input
                type="text"
                value={field.text}
                onChange={(event) => this.handleFieldChange(index, 'text', event)}
              />

              {(
                <button type="button" onClick={() => this.handleRemoveField(index)}>
                  Remove Field
                </button>
              )}
            </div>

          ))}
          <button type="button" onClick={() => this.handleAddField()}>
            Add Field
          </button>


        </div>
        <h4>Upload file</h4>
        <section>
          <label for="image">Image:</label>
          <input id="image" alt="image" onChange={(e) => this.handleFileSelection(e)} type="file" accept="image/x-png,image/jpeg,image/gif,image/svg+xml,image/webp,image/*,.pdf" />
          <section id="draftImage"></section>
        </section>

        <button type="button" onClick={() => this.saveDraft()}>
          Save
        </button>
        <button type="button" onClick={() => this.finalizeNode()}>
          Finalize
        </button>
      </div>)
    }

  }

  async showAddSupplier() {
    let hasAccess = await this.state.actor.can_add_new_supplier();
    let myElement = document.getElementById("addSupplier");
    if (hasAccess) {
      myElement.style.display = "block"; // Show the element
    } else {
      myElement.style.display = "none";
    }

  }

  async showCreateDraft() {
    let supplierLoggedIn = await this.state.actor.is_supplier_logged_in();
    let myElement = document.getElementById("createDraftBlock");
    if (supplierLoggedIn) {
      myElement.style.display = "block"; // Show the element
    } else {
      myElement.style.display = "none";
    }

  }

  showTree() {
    if (this.state.tree.length > 0) {
      return (<Flow nodes={this.state.tree} edges={this.state.edges} />);
    }
  }
  render() {
    const { drafts } = this.state;
    return (
      <div className="App">
        <div id="createCanister" style={{ display: "none" }} >
          <input id="image" alt="image" onChange={(e) => this.wasmHandler(e)} type="file" />
          <button onClick={() => this.installWasm()}>Install Wasm</button>
        </div>
        <h1>Supply Chain</h1>
        <div className="hero"></div>

        <button type="submit" id="login" onClick={() => this.login()}>Login</button>
        <h2 id="greeting"></h2>
        <div id="addSupplier" style={{ display: "none" }} >
          <h3> Add supplier</h3>
          <table>
            <tbody>
              <tr>

                <td>user id:</td><td><input required id="newSupplierID"></input></td>
                <td>username :</td><td><input required id="newSupplierName"></input></td>
              </tr>
            </tbody>
          </table>
          <button onClick={() => this.addSupplier()}>Create Supplier</button>
          <div id="supplierResponse"></div>
          <br></br>
        </div>
        <hr></hr>
        <br></br>
        <button onClick={() => this.getSuppliers()}>Get all suppliers</button>
        <div id="suppliers"></div>
        <div>
          <br></br>
          <button onClick={() => this.getNodes()}>Get all nodes</button>
          <div id="allNodes"></div>
          {this.showNodes()}
          <br></br>
          <hr></hr>
          <p>Get node by Id:</p>
          <input type="number" required id="nodeId"></input>
          <button onClick={() => this.getNodeById()}>Get Node</button>
          <br></br>
          {this.showNode()}
          <br></br>
          <div>
            <p> Get Chain by last node ID</p>
            <table>
              <tbody>
                <tr>
                  <td>Last node ID:</td><td><input type="number" required id="parentId"></input></td>
                </tr>
              </tbody>
            </table>
            <button onClick={() => this.getChildNodes()}>Show Child Nodes</button>
            {this.showTree()}
          </div>
          <br></br>

          <br></br>
          <div id="draftsList" style={{ display: "none" }}>
            <h3>My drafts</h3>
            {drafts.length == 0 && (
              <div>No drafts created</div>
            )}

            {drafts.length > 0 && (
              <div>
                {drafts.map((draft, index) => (
                  <div key={index}>
                    <label>{draft.title}</label>
                    <button type="button" onClick={() => this.setCurrentDraft(draft.id)}>
                      Edit draft
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>


        </div>



        <div id="createDraftBlock" style={{ display: "none" }}>
          <h3>Create Draft node:</h3>
          <table>
            <tbody>
              <tr>
                <td>Title:</td><td><input required id="newNodeTitle"></input></td>
              </tr>
            </tbody>
          </table>
          <button onClick={() => this.createDraftNode()}>Create Draft Node</button>
          <div id="createResult"></div>
          <br></br>
        </div>


        <div>{this.showDraft()}</div>
      </div>
    );
  }
}

render(<SupplyChain />, document.getElementById('create_node'));
