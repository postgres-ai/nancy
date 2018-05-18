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
    var query = "update experiment_run set status=$1::text, status_changed = now() where id=$2::int8";
    client.query(query, [status, id], function(err, result) {
        if (err) {
            logger.error('ERROR > Experimetn run update status error. ', err);
        }
    });
}

function setExperimentStatus(id, status, client){
    var query = "update experiment set status=$1::text where id=$2::int8";
    client.query(query, [status, id], function(err, result) {
        if (err) {
            logger.error('ERROR > Experiment update status error. ', err);
        }
    });
}

function checkExperimentsStatus(client) {
    var query = "update experiment set status='failed',status_changed=now() where (status='in_progress' or status='started') and status_changed < NOW() - INTERVAL '50 min';";
    client.query(query, function(err, result) {
        if (err) {
            logger.error('ERROR > Failed experiments update status error. ', err);
        }
    });
}


dbinit(config, function(err, client){
    if (err) {
        logger.error('Cannot connect to database.');
        return false;
    }

    var doProcess = function () {
        checkExperimentsStatus(client);
        var query = `
select
    er.id as experiment_run_id,
    er.experiment_id
from experiment_run er
where er.status is null limit 2;`; // limit 1
        client.query(query, function(err, result) {
            if (err) {
                logger.error('ERROR > error running select user query', err);
                return false;
            }
            if (result && result.rowCount>0) {
                for (var i in result.rows) {
                    var experimentRun = result.rows[i];

                    var jwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MiwibmFtZSI6ImRldl9wb3N0aWxhX3J1IiwiY3JlYXRlZCI6IjIwMTgtMDQtMjhUMTE6MTk6NTcuODU3ODU0KzAwOjAwIiwicm9sZSI6ImFwaXVzZXIifQ.z504wiWz8qVY1WaWdyW8WbuDnCxAFbjToqqOYFMnz5w';
                    logger.log('Experiment run: ', experimentRun);
                    var experimentId = experimentRun.experiment_id;
                    var experimentRunId = experimentRun.experiment_run_id;

                    setExperimentRunStatus(experimentRunId, 'initialized', client);
                    setExperimentStatus(experimentId, 'started', client);
                    var cmd = "";
                    cmd += "`aws ecr get-login --no-include-email` &&";
                    cmd += " export EC2_KEY_PAIR=awskey2 && export EC2_KEY_PATH=/home/dmius/.ssh/awskey2.pem";
                    cmd += " && export JWT_TOKEN=" + jwt;
                    cmd += " && export EXP_ID=" + experimentId;
                    cmd += " && export EXP_RUN_ID=" + experimentRunId;
                    cmd += " && ../run_experiment.sh >>/home/dmius/nancy/consumer/log/ncons_" + experimentId + "_" + experimentRunId + ".log 2>&1";
                    logger.log("Experiment start command: " + cmd);

                    dir = exec(cmd, function(err, stdout, stderr) {
                        if (err) {
                            console.log('Error start experiment: '  + experimentId + ' run: ' + experimentRunId, err);
                        }
                    });
                }
            }

            setTimeout(doProcess, 1000);
            return true;
        });
    }

    doProcess();

    logger.log('Consumer started');
    return true;
});

logger.log('NANCY CONSUMER > Started');
