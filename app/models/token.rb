class Token < ApplicationRecord
  include Solrengine::Tokens::Tokenizable
end
