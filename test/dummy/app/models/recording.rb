# The dummy app's one model, here so the suite can exercise a real attachment
# rather than a stand-in for one: has_one_attached is what produces an
# Attached::One, and an Attached::One is one of the source types url_for takes.
class Recording < ApplicationRecord
  has_one_attached :audio
end
