pipeline {
  agent any
  environment {
    API_URL  = 'https://api.waziup.io/api/v2'
    MQTT_URL = 'tcp://api.waziup.io:3883'
  }
  stages {
    stage('Prepare') {
      steps {
        dir ('WaziCloud') {
          git url: 'https://github.com/Waziup/WaziCloud.git'
          dir("tests") {
             sh 'npm install'
          }
        }
      }
    }
    stage('Test') {
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
          dir("WaziCloud/tests") {
            sh 'npm run test_jenkins'
          }
        }
      }
    }
  }
  post {
    always {
      junit 'tests/report.xml'
    }
    success {
      echo 'Success!'
    }
    failure {
      echo 'Failure!'
    }
    unstable {
      echo 'Unstable'
    }
  }
}
