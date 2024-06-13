# frozen_string_literal: true

require 'jekyll'
require 'fileutils'
require 'mini_magick'
require 'imgkit'
require 'base64'

module OgImages
  # This class generates an og-image for each post
  # It is a Jekyll plugin, so it will be called when the site is built
  # The image is generated using the post's title and the post's author
  class Generator < Jekyll::Generator
    def generate(site)
      # Get the posts
      posts = site.posts.docs
      projects = site.collections['projects'].docs

      # Generate an og-image for each post
      posts.each do |post|
        generate_og_image(post)
      end

      projects.each do |project|
        generate_og_image(project)
      end
    end

    # This method generates an og-image for a post
    def generate_og_image(post)
      title = post.data['title']
      author = post.data['author']

      # create the directory if it doesn't exist
      if !File.directory?("#{Dir.pwd}/assets/og_images")
        FileUtils.mkdir_p("#{Dir.pwd}/assets/og_images")
      end

      # Create the image using the post's title, author, background color and font color
      html = image_html(title, author)

      parameterized_post_id = post.id.gsub('/', '-')[1..]
      og_image_path = "assets/og_images/#{parameterized_post_id}.png"

      return if File.exist?(og_image_path)

      # Github Actions doesn't support imgkit.to_file if the file doesn't exist
      # so we need to create the file first
      FileUtils.touch(og_image_path)

      imgkit = IMGKit.new(html, width: 1200, height: 630, quality: 100, zoom: 1, disable_smart_width: true)
      imgkit.stylesheets << 'assets/css/og_image.css'
      imgkit.to_file(og_image_path)

      compress_image(og_image_path)
    end

    private

    def compress_image(image_path)
      image = MiniMagick::Image.new(image_path)
      image.quality(95)
      image.write(image_path)
    end

    def profile_image_base64
      File.open("assets/images/juan-aparicio.jpg", "rb") do |file|
        Base64.encode64(file.read)
      end
    end

    def image_html(title, author)
      <<~HTML
        <html>
          <head>
            <link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;600;700&display=swap" rel="stylesheet">
            <meta charset='utf-8' />
          </head>
          <body>
            <div class="root">
              <div style="display: block; margin: 0;">
                <img src="data:image/jpg;base64,#{profile_image_base64}" alt="Juan Aparicio" class="profile-image" />
              </div>
              <div class="content">
                <h1>#{title}</h1>
                <h3>#{author}</h3>
              </div>
            </div>
          </body>
        </html>
      HTML
    end
  end

  class Tag < Jekyll::Tags::IncludeTag
    def render(context)
      # Get the post
      post = context.registers[:page]

      # Get the path to the image
      og_image_name = if post.respond_to?(:id)
        post_id = post.id.gsub('/', '-')[1..]
        "#{post_id}.png"
      else
        "default_og_image.png"
      end

      # because the og-image is in the assets folder, we need to add the site's baseurl
      og_image_name = "#{context.registers[:site].config['url']}/assets/og_images/#{og_image_name}"

      # render the image og tag
      <<~HTML
      <meta property="og:image" content="#{og_image_name}" />
      <meta property="og:image:width" content="1200" />
      <meta property="og:image:height" content="630" />
      HTML
    end
  end
end

Liquid::Template.register_tag('og_image', OgImages::Tag)
