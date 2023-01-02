# frozen_string_literal: true

require 'liquid'
require 'ruby-vips' # for making thumbnails.


class ThumbLink < Liquid::Tag
  def initialize(tag_name, args, tokens)
    super
    @args = args.strip
    @thumbnail = case tag_name  # get the appropriate behavior
                 when 'imgLink'
                   IMGThumbnail
    end
  end

  def render(context)
    @arg_hash=parse_args(@config, @args, context)
    thumbnail = @thumbnail.new(context, @arg_hash)
    # thumbnail.generate_thumb #-- uncomment to avoid cache.
    "<figure class='thumblink'><a href='https://grussell1407.github.io/EN3212Electronics.github.io#{thumbnail.href}'> <img src='https://grussell1407.github.io/EN3212Electronics.github.io#{thumbnail.src}' width='#{thumbnail.width}' height='#{1.29 * thumbnail.width}' class='thumb'> <figcaption style='width: #{thumbnail.width}px;'>#{thumbnail.caption}</figcaption></a></figure>"
  end

  def parse_args(_config, args, context)
    # This returns a hash of the arguments passed to the string String values can be delimited by single or double quotes.
    # Requires at a minimum src='The thing to be linked to'.   Which can be any of these:
    #     A path to an image file -- a thumbnail will be generated
    #     A url -- a screenshot of the browser window will be taken, and used for the thumbnail
    #     A Geogebra Material_ID -- A thumbnail is pulled from the geogebra website.
    arguments={}
    args = Liquid::Template.parse(args).render(context) # this interprets any liguid tags like page.url
    args.scan(/(\w+)=("[^"]+"|'[^']+'|[\w._-]+)/) do |key, value|
      v = if (value[0] == "'" && value[-1]) == "'" || (value[0] == '"' && value[-1] == '"')
            value[1..-2]
          else
            context[value]
          end
      v = Liquid::Template.parse(v).render(context) if v.to_s.start_with? '{{'
      arguments[key.to_sym] = v
      arguments[:markup] = args
    end
    raise 'ThumbLink: Could not parse src for thumbnail' if arguments[:src].nil?
    arguments
  end
end



class Thumbnail
  attr_accessor :src, :href, :width, :caption

  def initialize(context, args)
    @args = args
    @site = context.registers[:site]
    @page = context.registers[:page]
    @config = @site.config['thumbnails'] # set thumbnail folder and default width in config.yaml
    @width  = @args[:width] ? @args[:width].to_i : @config['width'] ||= 200
    @caption = args[:caption] # caption might be nil
    @thumb_path = get_thumb_path
    @src =  File.join(@site.baseurl, @thumb_path) # thumbnail url
    @href = get_href # link url
    self.save  #generate the image and write it to image/thumbs folder, if it hasn't been done yet.
  end

  def save
    # this takes the source_name of an image and creates a thumbnail if it isn't already
    # in the thumb_folder
    # this method returns the url of the thumbnail, and the url to be linked to/
    # This method is overridden for other types of sources (ggb, or webpages)


    dest = File.join(@site.source, @thumb_path)
    if File.exist? dest
      print "Cached: #{@thumb_path}#{' ' * 50}\r"
    else
      # only create the thumbnail and write it to the thumbs folder if it doesn't already exist.
      puts "Generating:  #{@thumb_path}#{' ' * 50}"
      thumb_fn = File.basename(dest)
      FileUtils.mkdir_p(File.dirname(dest))
      thumbnail_img = generate_thumb
      thumbnail_img.write_to_file(dest, strip: true)
      @site.config['keep_files'] << thumb_fn unless @site.config['keep_files'].include? thumb_fn
      @site.regenerator.add(thumb_fn) if @site.respond_to?(:regenerator)
      @image = generate_thumb
    end
  end

  def get_src
    File.join(@site.baseurl, get_thumb_path)
  end
end

class IMGThumbnail < Thumbnail

  def get_href
    # Determine the url to the linked file.
    File.join(@site.baseurl, get_path)
  end

  def get_path
    # looks for the image in either the 'image' folder at the same level as the page, or in the 'image' folder at the top level of the site.
    # then returns the path to the image

    src = @args[:src]
    folder = begin
      File.dirname(@page.path)
    rescue StandardError
      @page['dir']
    end
    local_img = File.join(folder, 'images', src)
    top_img = File.join('/images', src)
    local = File.exist? File.join(@site.source, local_img)
    top = File.exist? File.join(@site.source, top_img)
    return local_img if local
    return top_img if top

    raise "Couldn't find image #{src} in #{top_img}  or #{local_img} while rendering. (#{@page['name']})."
  end

  def get_thumb_path
    path = get_path
    # given the src info passed to the tag, determine where to write the thumbnail.
    folders = File.dirname(path)
    thumb_folder = @config['folder'] ||= {}
    thumb_name = "#{File.basename(path)}_thumb.png"
    File.join(folders, thumb_folder, thumb_name)
  end

  def generate_thumb
    # this finds the original image and shrinks it and returns a Vips::Image
    begin
    source_path = File.join(@site.source,get_path) # filesystem path
    original_img = Vips::Image.new_from_file source_path
    original_img.thumbnail_image width # make the thumbnail
    rescue
      "Problem generating #{@thumb_path}"
      raise
    end
  end
end

Liquid::Template.register_tag('imgLink', ThumbLink)
Liquid::Template.register_tag('ggbLink', ThumbLink)
Liquid::Template.register_tag('urlLink', ThumbLink)
