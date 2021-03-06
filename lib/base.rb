
require 'sinatra/content_for'
require "hashie" 
require_relative "auth/github"
require "sinatra/asset_pipeline"
require_relative "extensions/partials"

path = File.expand_path "../jobs/*.rb", __FILE__
Dir[path].each { |job| require(job) }


class HuboardApplication < Sinatra::Base

  enable  :sessions
  enable :raise_exceptions
  set :protection, except: :session_hijacking 
  #set :server, 'puma'

  helpers Sinatra::ContentFor

  # required configuration
  
  set :secret_key, ENV['SECRET_KEY']

  GITHUB_CONFIG = {
    :client_id     => ENV['GITHUB_CLIENT_ID'],
    :client_secret => ENV['GITHUB_SECRET'],
    :scope => "public_repo"
  }
  set :session_secret, ENV["SESSION_SECRET"]
  set :socket_backend, ENV["SOCKET_BACKEND"]
  set :socket_secret, ENV["SOCKET_SECRET"]

  set :cache_config, {
    servers: ENV["CACHE_SERVERS"] = ENV["MEMCACHIER_SERVERS"],
    username: ENV["CACHE_USERNAME"] = ENV["MEMCACHIER_USERNAME"],
    password: ENV["CACHE_PASSWORD"] = ENV["MEMCACHIER_PASSWORD"]
  }

  set :server_origin, {
    scheme: ENV["HTTP_URL_SCHEME"] || "https",
    host: ENV["HTTP_HOST"] || "huboard.com"
  }

  # end configuration

  set :assets_precompile, %w(vendor/jquery.js vendor/jquery-ui.js splash.css marketing.css marketing.js application.js flex_layout.css bootstrap.css application.css ember-accounts.js board/application.js bootstrap.js *.png *.jpg *.svg *.eot *.ttf *.woff *.js).concat([/\w+\.(?!js|css).+/, /application.(css|js)$/])

  configure :production, :test, :staging do 
    set :asset_protocol, :https
  end

  configure :development do
    enable :logging
    require "better_errors" 
    use BetterErrors::Middleware
    BetterErrors.application_root = __dir__
  end


  register Sinatra::AssetPipeline


  configure :production, :test, :staging do 
    sprockets.js_compressor = :uglify
    sprockets.css_compressor = :scss
  end


  helpers Huboard::Common::Helpers
  helpers Sinatra::Partials

  use Rack::Session::Cookie, 
    :key => 'rack.session',
    :path => '/',
    :secret => settings.session_secret,
    :expire_after => 2592000,
    :secure => production?

  set :views, File.expand_path("../views",File.dirname(__FILE__))

  use Sinatra::Auth::Github::BadAuthentication
  use Sinatra::Auth::Github::AccessDenied

  use Warden::Manager do |config|
    config.failure_app = Sinatra::Auth::Github::BadAuthentication
    config.default_strategies :github
    config.scope_defaults :default, :config => GITHUB_CONFIG
    config.scope_defaults :private, :config => GITHUB_CONFIG.merge(:scope => 'repo')
  end

  helpers do

    def github_config
      return :client_id => GITHUB_CONFIG[:client_id], :client_secret => GITHUB_CONFIG[:client_secret]
    end

  end


  set :raise_errors, true

  use Rack::Robustness do |g|

    g.no_catch_all
    g.status 302
    g.content_type 'text/html'
    g.body 'A fatal error occured.'
    g.headers "Location" => "/logout"

    g.on(Ghee::Error)

  end


end
