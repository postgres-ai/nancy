var convict = require('convict');

// Define a schema
var conf = convict({
    env: {
        doc: "The applicaton environment.",
        format: ["production", "development", "test"],
        default: "development",
        env: "NODE_ENV"
    },
    db_name: {
        doc: "The database name.",
        format: String,
        default: "postgres_ai",
        env: "DATABASE"
    },
    db_user: {
        doc: "The database user login.",
        format: String,
        default: "ai",
        env: "DB_USER"
    },
    db_password: {
        doc: "The database user password.",
        format: String,
        default: null,
        env: "DB_PASSWORD"
    },    
    db_port: {
        doc: "The database port.",
        format: "port",
        default: 5432,
        env: "DB_PORT"
    },    
    db_host: {
        doc: "The database host.",
        format: String,
        default: '127.0.0.1',
        env: "DB_HOST"
    },    
    db_max: {
        doc: "The database max connections.",
        format: "nat",
        default: 10,
        env: "DB_MAX"
    },    
    db_idle_timeout: {
        doc: "How long a client is allowed to remain idle before being closed.",
        format: "nat",
        default: 30000,
        env: "DB_IDLE_TIMEOUT"
    },
    jwt_secret: {
        doc: "JWT token secret.",
        format: String,
        default: null,
        env: "JWT_SECRET"
    },
    debug_mode: {
        doc: "Control debug mode for microservice",
        format: "nat",
        default: 0,
        env: "DEBUG_MODE"
    },
});

// Load environment dependent configuration
var env = conf.get('env');

conf.loadFile('./config/' + env + '.json');

// Perform validation
conf.validate({strict: true});

module.exports = conf;