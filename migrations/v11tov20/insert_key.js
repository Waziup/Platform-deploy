var fs = require('fs');
const axios = require('axios');

var contents = fs.readFileSync('devices.json');
devices = JSON.parse(contents);

var contents = fs.readFileSync('resources.json');
resources = JSON.parse(contents);


async function insert_keys() {
  for (var dev of devices) {
    console.log("Updating sensor " + dev.id)
 
    var url = 'http://localhost:1026/v2/entities/' + dev.id + '/attrs'
    try {
      var axiosConf = {headers: {'Fiware-Service': 'waziup'},
                       params: {'type': 'SensingDevice'}}
      let attrs = await axios.get(url, axiosConf);
    
      for(let [key, value] of Object.entries(attrs.data)) {

        if(value.type == "Measurement") {
          console.log("    Updating att " + key)
          var url = 'http://localhost:1026/v2/entities/' + dev.id + '/attrs/' + key
          try {
            var axiosConf = {headers: {'Content-Type': 'application/json', 'Fiware-Service': 'waziup'},
                             params: {'type': 'SensingDevice'}}
            let attrs = await axios.put(url, {...value, 'type': 'Sensor'}, axiosConf);
          } catch (error) {
            console.log("Error: " + error);
          }
        }
      }
    
    } catch (error) {
      console.log("Error: " + error);
    }

    var res = resources.find(function(res) {
      return res.name == dev.id;
    });
    if(res) {
      console.log("    adding keycloak res " + res._id)
     
      try {
        var url = 'http://localhost:1026/v2/entities/' + dev.id + '/attrs'
        var data = {"keycloak_id": {"value": res._id, "type": "String"}}
        var axiosConf = {headers: {'Content-Type': 'application/json', 'Fiware-Service': 'waziup'},
                         params: {'type': 'SensingDevice'}}
        let res2 = await axios.post(url, data, axiosConf);
        console.log(res2.status);
      } catch (error) {
        console.log("Error: " + error.status);
      }
  
    } else {
      console.log("Sensor " + dev.id + " resource not found!");
    }
  
  }
}

insert_keys();
