var config = require('./config/config.js');
var logger = require('tracer').console();
var pg = require('pg');
var client = new pg.Client();
var sys = require('sys')
var exec = require('child_process').exec;

function dbinit(conf, callback) {
    if (! conf) {
        config = config = require('../config/config.js');
    } else {
        config = conf;
    }
    var dbconfig = {
        user: config.get('db_user'), //'postila_ru', //env var: PGUSER
        database: config.get('db_name'), //'postila_ru', //env var: PGDATABASE
        password: config.get('db_password'), //'aiSai4ee', //env var: PGPASSWORD
        port: config.get('db_port'), //env var: PGPORT
        host: config.get('db_host'),
        max: config.get('db_max'), //10, // max number of clients in the pool
        idleTimeoutMillis: config.get('db_idle_timeout')//30000, // how long a client is allowed to remain idle before being closed
    };
    isDebugMode = config.get('debug_mode');

    var client = new pg.Client(dbconfig);

    // connect to our database
    client.connect(function (err) {
        if (err) {
            logger.error('ERROR > error connect', err);
            if (callback) {
                callback(err, false);
            }
            return;
        }
        if (callback) {
            callback(false, client);
        }
    });
};

function setExperimentRunStatus(id, status, client){
    $query = "update experiment_run set status=$1::text, status_changed = now() where $2::int8";
    client.query(query, [status, id], function(err, result) {
        if (err) {
            logger.error('ERROR > Experimetn run update status error. ', err);
            if (data.callback) {
                data.callback(err, {client: client});
            }
        }
    });    
}

dbinit(config, function(err, client){
    if (err) {
        logger.error('Cannot connect to database.');
        return false;
    }
    
    var query = "select er.*,e.database_version_id,dv.version from experiment_run er join experiment e on e.id = er.experiment_id join database_version dv on dv.id = e.database_version_id where er.status is null limit 1;";
    client.query(query, function(err, result) {
        if (err) {
            logger.error('ERROR > error running select user query', err);
            if (data.callback) {
                data.callback(err, {client: client});
            }
            return false;
        }
        if (result && result.rowCount>0) {
            for (var i in result.rows) {
                var experiment = result.rows[i];
                var jwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MiwibmFtZSI6ImRldl9wb3N0aWxhX3J1IiwiY3JlYXRlZCI6IjIwMTgtMDQtMjhUMTE6MTk6NTcuODU3ODU0KzAwOjAwIiwicm9sZSI6ImFwaXVzZXIifQ.z504wiWz8qVY1WaWdyW8WbuDnCxAFbjToqqOYFMnz5w';
                console.log('Experiment: ', experiment);
                var experiment_id = experiment.experiment_id;
                var experiment_step = experiment.step;
                var queries = experiment.queries;
                var change = experiment.change;
                var dbVersion = experiment.version;
                //setExperimentRunStatus(experiment.id, 'started', client);
                var cmd = "`aws ecr get-login --no-include-email` && export EC2_KEY_PAIR=awskey2 && export EC2_KEY_PATH=/home/dmius/.ssh/awskey2.pem && export JWT_TOKEN=" + jwt + " && export EXP_ID=" + experiment_id+ " && export EXP_STEP=" + experiment_step + " && ../run_experiment.sh";
                console.log("Experiment start command: " + cmd);
                
                dir = exec(cmd, function(err, stdout, stderr) {
                    if (err) {
                        // should have err.code here?  
                        console.log('Error:', err);
                    }
                    console.log('STDOUT:', stdout);
                    console.log('STDERR:', stderr);
                });
            }
        }
        client.end(function (err) { // close connection
            if (err) {
                logger.error('ERROR > Close connection error: ', err);
            }
        });
        return true;
    });
    console.log('All');
    return true;
});

logger.log('NANCY CONSUMER > Started');
