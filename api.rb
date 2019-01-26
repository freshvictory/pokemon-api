require 'sinatra'
require 'json'
require 'neo4j-core'
require 'neo4j/core/cypher_session/adaptors/http'

NEO4J_URL = ENV['NEO4J_URL'] || 'http://localhost:7474'

Neo4j::Core::CypherSession::Adaptors::Base.subscribe_to_query(&method(:puts))

def get_session
    faraday_configurator = proc do |faraday|
        faraday.adapter :typhoeus

        puts faraday.options.inspect
        faraday.ssl[:verify] = false
    end

    http_adaptor = Neo4j::Core::CypherSession::Adaptors::HTTP.new(NEO4J_URL, faraday_configurator: faraday_configurator)
    Neo4j::Core::CypherSession.new(http_adaptor)
end

before do
    content_type :json
    headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    headers['Access-Control-Allow-Origin'] = '*'
    headers['Access-Control-Allow-Headers'] = 'accept, authorization, origin'
end

options '*' do
    response.headers['Allow'] = 'HEAD,GET,PUT,DELETE,OPTIONS,POST'
    response.headers['Access-Control-Allow-Headers'] = 'X-Requested-With, X-HTTP-Method-Override, Content-Type, Cache-Control, Accept'
end

get '/' do
    """
               _,.+-----__,._
              /  /    ,'     `.
     ,+._   ./...\\_  /   ,..   \\
     | `.`+'       `-' .' ,.|  |
     |  |( ,    ,.`,   |  `-',,........_       __......_
      \\ |..`/,-'  '\"\"\"' `\"\"'\"  _,.---\"-,  .-+-'      _.-\"\"`--._
       .\"|       /\"\\`.      ,-'       / .','      ,-'          \\
      .'-'      |`-'  |    `./       / / /       /   ,.-'       |
     j`v+\"      `----\"       ,'    ,'./ .'      /   |        ___|
     |                      |   _,','j  |      /    L   _.-\"'    `--.
      \\                     `.-'  j  |  L     F      \\-'             \\
       \\ .-.               ,'     |  L   .    /    ,'       __..      `
        \\ `.|            _/_      '   \\  |   /   ,'       ,\"    `.     '
         `.             '   `-.    `.__| |  /  ,'         |            |
           `\"-,.               `----'   `-.' .'   _,.--\"\"\"'\" --.      ,'
              |          ,.                `.  ,-'              `.  _'
             /|         /                    \\'          __.._    \\'
   _...--...' +,..-----'                      \\-----._,-'     \\    |
 ,'    |     /        \\                        \\      |       j    |
/| /   |    j  ,      |                         ,._   `.    -'    /
\\\\'   _`.__ | |      _L      |-----\\            `. \\    `._    _,'
 \"\"`\"'     \"`\"---'\"\"`._`-._,-'      `.              `.     `--'
                       \"`--.......____:.         _  / \\
                               `-----.. `>-.....`,-'   \\
                                      `|\"    `.  ` . \\ |
                                        `._`..'    `-\"'
                                           \"'
    """
end

get '/type/:type' do |type|
    session = get_session

    query = """
    match (type:Type)
    where type.type = {type}
    return type
    """

    row = session.query(query, type: type).first
    halt 404 unless row

    type_row = row[:type].properties
    t = type_row[:type]

    type_rel_query = """
    match (p:Type)
    where p.type = {type}
    optional match (p)-[:weak]->(weak:Type)
    with p, collect(weak) as weakAgainst
    optional match (counter:Type)-[:strong]->(p)
    with p, collect(counter) as counters, weakAgainst
    optional match (p)-[:strong]->(strong:Type)
    with p, collect(strong) as effectiveAgainst, counters, weakAgainst
    optional match (p)-[:ineffective]->(ineffective:Type)
    with p, collect(ineffective) as ineffectiveAgainst, effectiveAgainst, counters, weakAgainst
    optional match (resistant:Type)-[:ineffective]->(p)
    with p, collect(resistant) as resistantTo, ineffectiveAgainst, effectiveAgainst, counters, weakAgainst
    return {
        resistantTo: resistantTo,
        weakAgainst: weakAgainst,
        effectiveAgainst: effectiveAgainst,
        counters: counters,
        ineffectiveAgainst: ineffectiveAgainst
    } as relationships
    """

    rel_row = session.query(type_rel_query, type: t).first
    relationships = rel_row[:relationships]
    mapper = lambda { |x| x.properties }
    resistantTo = relationships[:resistantTo].map(&mapper)
    counters = relationships[:counters].map(&mapper)
    effectiveAgainst = relationships[:effectiveAgainst].map(&mapper)
    weakAgainst = relationships[:weakAgainst].map(&mapper)
    ineffectiveAgainst = relationships[:ineffectiveAgainst].map(&mapper)

    result = {
        "type" => t,
        "name" => type_row[:name],
        "short" => type_row[:short],
        "relationships" => {
            "resistantTo" => resistantTo,
            "counters" => counters,
            "effectiveAgainst" => effectiveAgainst,
            "weakAgainst" => weakAgainst,
            "ineffectiveAgainst" => ineffectiveAgainst
        }
    }

    result.to_json
end

