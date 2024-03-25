---
layout: blog
author: Juan Aparicio
---

In my [previous post](/blog/2024-03-21-use-ai-to-query-your-database-with-rails) , I showcased a way to build an AI search engine using Ruby On Rails.
In this post I'll be building a search engine for the [Airlines Reviews dataset](https://www.kaggle.com/datasets/sujalsuthar/airlines-reviews?resource=download) using the same approach.

I'll guide you through the entire process, from cleaning-up the data, to seeding the database, and finally building the search engine UI.

## Cleaning-up the data
This is one of the most important steps when working with data. The dataset I'm using is a CSV file with the following columns:
- Title
- Name
- Review Date
- Airline
- Verified
- Reviews
- Type of Traveller
- Month Flown
- Route
- Class
- Seat Comfort
- Staff Service
- Food & Beverages
- Inflight Entertainment
- Value For Money
- Overall Rating
- Recommended

For this tutorial, I'm only interested in the `Title`, `Reviews` and `Airline` columns. I'll be using the `Title` and `Reviews` columns to build the search engine, and the `Airline` column to filter the results by airline.

Because the data in the CSV file is sorted by Airline and then by Review Date, I'll have to take a sample (200 rows) of each airline, to avoid having all the reviews of the same airline together.

```python
import pandas as pd

# Replace 'your_file.csv' with the path to your CSV file
file_path = 'airlines_reviews.csv'

# Load the CSV data into a pandas DataFrame
df = pd.read_csv(file_path)

# Normalize the 'Title' and 'Reviews' columns by removing double quotes
# and trimming spaces at the beginning and the end
df['Title'] = df['Title'].str.replace('"', '').str.strip()
df['Reviews'] = df['Reviews'].str.replace('"', '').str.strip()

# Normalize the Verified column by trimming spaces at the beginning and the end, and converting to lowercase
df['Verified'] = df['Verified'].str.strip().str.lower()

# Keep only rows where 'Verified' is TRUE
df_verified = df[df['Verified'] == 'true']

# Keep only the 'Airline', 'Reviews', and 'Title' columns
df_filtered = df_verified[['Airline', 'Reviews', 'Title']]

# Create an empty DataFrame to store the final result
df_final = pd.DataFrame(columns=['Airline', 'Reviews', 'Title'])

# List of all possible values for Airline
airlines = [
    "Singapore Airlines",
    "Qatar Airways",
    "All Nippon Airways",
    "Emirates",
    "Japan Airlines",
    "Turkish Airlines",
    "Air France",
    "Cathay Pacific Airways",
    "EVA Air",
    "Korean Air"
]

# For each airline, select up to 200 most recent reviews and append to df_final
for airline in airlines:
    df_airline = df_filtered[df_filtered['Airline'] == airline].head(200)
    df_final = pd.concat([df_final, df_airline], ignore_index=True)

# Save the result to a new CSV file
df_final.to_csv('airline_reviews_sample.csv', index=False)
```
Explanation of the code:
1. Load the CSV data into a pandas DataFrame.
2. Normalize the 'Title' and 'Reviews' columns by removing double quotes and trimming spaces at the beginning and the end.
3. Normalize the 'Verified' column by trimming spaces at the beginning and the end, and converting to lowercase.
4. Keep only rows where 'Verified' is TRUE.
5. Keep only the 'Airline', 'Reviews', and 'Title' columns.
6. Create an empty DataFrame to store the final result.
7. List of all possible values for Airline.
8. For each airline, select up to 200 most recent reviews and append to df_final.
9. Save the result to a new CSV file, called `airline_reviews_sample.csv`.

## Creating the Rails application

To create a new Rails application, run the following command:

```bash
rails new airline_reviews_search --database=postgresql --css=tailwind --javascript=importmap --asset-pipeline=propshaft --skip-jbuilder --skip-action-mailbox
```

This command creates a new Rails application called `airline_reviews_search` with the following options:
- `--database=postgresql`: Use PostgreSQL as the database.
- `--css=tailwind`: Use Tailwind CSS for styling.
- `--javascript=importmap`: Use import maps for JavaScript modules.
- `--asset-pipeline=propshaft`: Use Propshaft as the asset pipeline.
- `--skip-jbuilder`: Skip generating Jbuilder templates.
- `--skip-action-mailbox`: Skip generating Action Mailbox files.

Change to the project directory:

```bash
cd airline_reviews_search
```

As I mentioned in the previous post, I'll be using the neighbor gem to get everything needed for looking up vectors, and get the necessary scopes for getting the most similar embeddings

[Install the pgvector extension](https://formulae.brew.sh/formula/pgvector):

```bash
brew install pgvector
```
(for guides on how to install in your specific platform, check the official [pgvector documentation](https://github.com/pgvector/pgvector?tab=readme-ov-file#installation))

Add the neighbor gem to your Gemfile:

```bash
bundle add neighbor
```

Run the neighbor gem initiliazer:

```bash
rails generate neighbor:vector
rails db:migrate
```

## Creating the Rails models
For this example, we'll keep it pretty simple. We just need:
- `Airline`: to store the airline name.
- `Review`: to store the review title and content.
- `Embedding`: to store the embeddings for the reviews.

Initalize the database:
```bash
rails db:create
```

Create a migration for enabling the pgvector extension:

```bash
rails g migration enable_pgvector
```

Add the following code to the migration file:

```ruby
class EnablePgvector < ActiveRecord::Migration[6.1]
  def change
    enable_extension "vector"
  end
end
```


Generate the models:

```bash
rails g model Airline name:string
rails g model Review title:string body:text airline:references
rails g model Embedding embedding:vector embeddable:references{polymorphic}:uniq
```

Add the following indexes:
```ruby
add_index :airlines, :name, unique: true
```

Now the models should look like this:

```ruby
class Airline < ApplicationRecord
  has_many :reviews
end
```

```ruby
class Review < ApplicationRecord
  belongs_to :airline
  has_one :embedding, as: :embeddable

  validates :title, :body, presence: true
end
```

```ruby
class Embedding < ApplicationRecord
  has_neighbor :vector

  belongs_to :embeddable, polymorphic: true
end
```

## Seeding the database
Create a new file called `seeds.rb` in the `db` directory and add the following code:

```ruby
require 'csv'

# Load the CSV data into a hash
csv_path = Rails.root.join('db', 'airline_reviews_sample.csv')
data = CSV.read(csv_path, headers: true)

# Create Airline records
airlines = data.map { |row| row['Airline'] }.uniq

ActiveRecord::Base.transaction do
  airlines.each { |name| Airline.create(name: name) }

  # Create Review records
  data.each do |row|
    airline = Airline.find_by!(name: row['Airline'])
    Review.create(title: row['Title'], body: row['Reviews'], airline: airline)
  end
end
```

## Generating the Embeddings
We first need a service to generate the embeddings for the reviews:

```ruby
# app/services/open_ai/create_embedding.rb
require 'net/http'

class OpenAi::CreateEmbedding
  def initialize(api_key)
    @api_key = api_key
  end

  def self.call(text)
    new(ENV["OPENAI_API_KEY"]).call(text)
  end

  def call(text)
    response = Net::HTTP.post(
      URI("https://api.openai.com/v1/embeddings"),
      {
        input: text,
        model: "text-embedding-ada-002"
      }.to_json,
      "Authorization" => "Bearer #{@api_key}",
      "Content-Type" => "application/json"
    )

    JSON.parse(response.body)["data"].first["embedding"]
  end
end
```
Add the dotenv gem to your Gemfile, so you can store the OpenAI API key in a `.env` file:

```ruby
gem 'dotenv-rails', groups: [:development, :test]
```

Make sure to add the `OPENAI_API_KEY` to your `.env` file!

Test the service by running the following code in the Rails console:

```ruby
review = Review.first
vector = OpenAi::CreateEmbedding.call("#{review.title}  #{review.body}")
# => [0.123, 0.456, 0.789, ...]
vector.size
# => 1536
```

## Seeding the embeddings
First, create a method in the `Review` model to generate the content we want to embed:

```ruby
# app/models/review.rb
class Review < ApplicationRecord
  def embed_string
    "#{title} #{body}"
  end
end
```

Then, you can run the following code in the Rails console to seed the embeddings:

```ruby
Review.find_each do |review|
  embedding = OpenAi::CreateEmbedding.call(review.embed_string)
  review.create_embedding!(embedding:)
end
```

Now sit back and relax, or go and prepare yourself a mate or a coffee, because this will take a while.

## Building the Rails Controller and View

First, let's create a controller to search the reviews

```ruby
# app/controllers/review_controller.rb
class ReviewsController < ApplicationController
  def index
    @reviews = prompt.present? ? reviews : Review.none
    @completions_response = @reviews.any? ? completions_response : nil
  end

  private

  def prompt
    params[:query]
  end

  def prompt_embedding
    OpenAi::CreateEmbedding.call(prompt)
  end

  def matching_embeddings
    if prompt.present?
      Embedding.nearest_neighbors(:embedding, prompt_embedding, distance: :cosine)
    else
      Embedding.all
    end
  end

  def reviews
    embeddings = matching_embeddings
                          .where(embeddable_type: "Review")
                          .limit(7)
                          .pluck(:embeddable_id)
    Review.where(id: embeddings).includes(:airline)
  end

  def completions_response
    system = <<-PROMPT.gsub("\n", "  ")
    You are an AI that answers user submitted questions, based off of the reviews of airlines.
    Here are the reviews:
      #{ @reviews.map { "- #{_1.airline.name}: #{_1.title}; {_1.body}" }}
    PROMPT

    OpenAi::Chat.call(prompt, system:)
  end
end
```
How the controller works:
1. The `index` action gets the search query from the `params` hash.
2. The controller generates an embedding for the search query using the `OpenAi::CreateEmbedding` service.
3. The controller gets the nearest neighbors of the search query embedding from the `Embedding` model.
4. The controller gets the reviews matching the nearest neighbors.
5. The controller generates a response for the completions prompt using the `OpenAi::Chat` service, using the nearest neighbors as the system prompt.

Then, create a view to display the search results:

```erb
<!-- app/views/reviews/index.html.erb -->
<div class="flex flex-col m-auto py-10 max-w-3xl">
  <div class="sticky top-0 flex flex-col bg-white p-5 rounded-md shadow-[0_3px_10px_rgb(0,0,0,0.2)]">
    <h1 class="text-5xl font-bold text-center bg-gradient-to-r from-blue-700 to-violet-700 inline-block text-transparent bg-clip-text max-w-max mx-auto pt-5">
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="inline-block h-10 w-10 text-blue-700">
        <path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904 9 18.75l-.813-2.846a4.5 4.5 0 0 0-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 0 0 3.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 0 0 3.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 0 0-3.09 3.09ZM18.259 8.715 18 9.75l-.259-1.035a3.375 3.375 0 0 0-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 0 0 2.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 0 0 2.456 2.456L21.75 6l-1.035.259a3.375 3.375 0 0 0-2.456 2.456ZM16.894 20.567 16.5 21.75l-.394-1.183a2.25 2.25 0 0 0-1.423-1.423L13.5 18.75l1.183-.394a2.25 2.25 0 0 0 1.423-1.423l.394-1.183.394 1.183a2.25 2.25 0 0 0 1.423 1.423l1.183.394-1.183.394a2.25 2.25 0 0 0-1.423 1.423Z" />
      </svg>
      <%= link_to "AI Airline Review Search", root_path, class: "hover:text-blue-700" %>
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="inline-block h-10 w-10 text-violet-700">
        <path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904 9 18.75l-.813-2.846a4.5 4.5 0 0 0-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 0 0 3.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 0 0 3.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 0 0-3.09 3.09ZM18.259 8.715 18 9.75l-.259-1.035a3.375 3.375 0 0 0-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 0 0 2.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 0 0 2.456 2.456L21.75 6l-1.035.259a3.375 3.375 0 0 0-2.456 2.456ZM16.894 20.567 16.5 21.75l-.394-1.183a2.25 2.25 0 0 0-1.423-1.423L13.5 18.75l1.183-.394a2.25 2.25 0 0 0 1.423-1.423l.394-1.183.394 1.183a2.25 2.25 0 0 0 1.423 1.423l1.183.394-1.183.394a2.25 2.25 0 0 0-1.423 1.423Z" />
      </svg>
    </h1>
    <div class="mt-10">
      <%= form_tag reviews_path, method: :get do %>
        <div class="flex gap-x-2">
          <%= text_field_tag :query, params[:query], class: "border border-gray-300 rounded-md p-2 grow", autocomplete: 'off' %>

          <%= submit_tag "Search with AI!", name: nil, class: "bg-blue-500 text-white p-2 rounded-md" %>
          <%= link_to "Clear", reviews_path, class: "bg-gray-300 text-gray-800 p-2 rounded-md" %>
        </div>
      <% end %>
    <% if @completions_response.present? %>
      <div class="mt-5 p-2 bg-gray-100 rounded-md">
        <p><%= @completions_response %></p>
      </div>
    <% end %>
    </div>
  </div>
  <% if @reviews.any? %>
    <div class="flex flex-col gap-y-2 mt-5">
      <% @reviews.each do |review| %>
        <div class="flex flex-col gap-2 border border-gray-300 p-2 rounded-md">
          <div class="flex gap-x-1">
            <strong>Airline:</strong> <span><%= review.airline.name %></p></span>
          </div>
          <div class="flex gap-x-1">
            <strong>Title:</strong> <span class="truncate hover:text-clip"><%= review.title %></span>
          </div>
          <p><%= review.body %></p>
        </div>
      <% end %>
    </div>
  <% end %>
</div>
```

Finally, add a route to the search engine:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  resources :reviews, only: :index
  root to: 'reviews#index'
end
```

Now run the rails server and go to `http://localhost:3000` to see the search engine in action!

You can find the full code for this tutorial in this [GitHub repository](https://github.com/juan-apa/Rails-Airline-Review-AI-Search)

# Demo
{% Video assets/videos/rails-ai-airline-reviews-search.mp4 %}


