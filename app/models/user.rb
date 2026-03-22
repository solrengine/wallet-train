class User < ApplicationRecord
  include Solrengine::Auth::Concerns::Authenticatable

  has_many :transfers, dependent: :destroy
end
