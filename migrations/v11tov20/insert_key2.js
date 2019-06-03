var fs = require('fs');
const axios = require('axios');

var contents = fs.readFileSync('devices.json');
devices = JSON.parse(contents);

var contents = fs.readFileSync('resources.json');
resources = JSON.parse(contents);


async function insert_keys() {

  var devs = []
  for (var dev of devices) {
    console.log("Updating sensor " + dev.id)

    var res = resources.find(function(res) {
      return res.name == dev.id;
    });
    if(res) {
      console.log("    adding keycloak res " + res._id)
     
      devs.push({...dev, "keycloak_id": {"value": res._id, "type": "String"}});
  
    } else {
      devs.push(dev);
    }
  
  }

  fs.writeFileSync('./devices2.json', JSON.stringify(devs));
}

insert_keys();
