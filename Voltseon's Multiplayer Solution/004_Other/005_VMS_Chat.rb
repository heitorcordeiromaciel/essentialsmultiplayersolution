
module VMS
  class << self
    attr_accessor :chat_overlay_sprite
  end

  def self.send_chat_message(text)
    return unless VMS::ENABLE_CHAT
    return unless VMS.is_connected?
    text = text.to_s.strip
    return if text.empty?
    text = text[0, VMS::CHAT_MAX_MESSAGE_LENGTH] if text.length > VMS::CHAT_MAX_MESSAGE_LENGTH
    VMS.send_message(["chat", {
      VMS::PACKET_KEYS[:cluster_id] => VMS.get_cluster_id,
      VMS::PACKET_KEYS[:id]         => $player.id,
      text: text
    }])
    VMS.append_chat_message($player.name, text)
  end

  def self.receive_chat_message(sender_name, text)
    return unless VMS::ENABLE_CHAT
    VMS.append_chat_message(sender_name.to_s, text.to_s)
  end

  def self.append_chat_message(name, text)
    log = $game_temp.vms[:chat_log]
    log.push([name, text])
    log.shift while log.length > VMS::CHAT_LOG_MAX_MESSAGES
    $game_temp.vms[:chat_dirty]         = true
    $game_temp.vms[:chat_last_activity] = Time.now
  end

  CHAT_FONT_SIZE   = 16
  CHAT_LINE_HEIGHT = 20
  CHAT_PAD         = 6

  def self.update_chat_overlay
    unless VMS::ENABLE_CHAT && VMS.is_connected? && !$game_temp.vms[:chat_hidden] && $scene.is_a?(Scene_Map)
      VMS.dispose_chat_overlay
      return
    end
    VMS.rebuild_chat_overlay if @chat_overlay_sprite.nil? || @chat_overlay_sprite.disposed? || $game_temp.vms[:chat_dirty]
    VMS.update_chat_fade
  end

  def self.update_chat_fade
    return unless @chat_overlay_sprite && !@chat_overlay_sprite.disposed?
    return if VMS::CHAT_FADE_DELAY <= 0
    last_activity = $game_temp.vms[:chat_last_activity]
    if last_activity.nil?
      @chat_overlay_sprite.opacity = 255
      return
    end
    elapsed = Time.now - last_activity
    if elapsed <= VMS::CHAT_FADE_DELAY
      @chat_overlay_sprite.opacity = 255
    else
      fade_elapsed = elapsed - VMS::CHAT_FADE_DELAY
      progress = VMS::CHAT_FADE_DURATION > 0 ? (fade_elapsed / VMS::CHAT_FADE_DURATION) : 1.0
      @chat_overlay_sprite.opacity = (255 * (1.0 - [progress, 1.0].min)).round
    end
  end

  def self.wrap_chat_line(bmp, text, max_width)
    lines   = []
    current = ""
    text.split(" ").each do |word|
      candidate = current.empty? ? word : "#{current} #{word}"
      if bmp.text_size(candidate).width <= max_width
        current = candidate
        next
      end
      lines << current unless current.empty?
      if bmp.text_size(word).width <= max_width
        current = word
      else
        chunk = ""
        word.each_char do |ch|
          test = chunk + ch
          if bmp.text_size(test).width > max_width && !chunk.empty?
            lines << chunk
            chunk = ch
          else
            chunk = test
          end
        end
        current = chunk
      end
    end
    lines << current unless current.empty?
    lines
  end

  def self.draw_rounded_rect(bmp, x, y, w, h, radius, color)
    bmp.fill_rect(x, y, w, h, color)
    return if radius <= 0
    clear = Color.new(0, 0, 0, 0)
    r2 = radius * radius
    corners = [
      [x, y, x + radius, y + radius],
      [x + w - radius, y, x + w - radius - 1, y + radius],
      [x, y + h - radius, x + radius, y + h - radius - 1],
      [x + w - radius, y + h - radius, x + w - radius - 1, y + h - radius - 1]
    ]
    corners.each do |bx, by, px, py|
      radius.times do |dx|
        radius.times do |dy|
          cx = bx + dx
          cy = by + dy
          ddx = cx - px
          ddy = cy - py
          bmp.set_pixel(cx, cy, clear) if (ddx * ddx + ddy * ddy) > r2
        end
      end
    end
  end

  def self.rebuild_chat_overlay
    VMS.dispose_chat_overlay
    $game_temp.vms[:chat_dirty] = false
    return if $game_temp.vms[:chat_log].empty?

    width      = VMS::CHAT_BOX_WIDTH
    outline    = VMS::CHAT_BOX_OUTLINE_WIDTH
    text_width = width - CHAT_PAD * 2 - outline * 2

    tmp = Bitmap.new(1, 1)
    tmp.font.size = CHAT_FONT_SIZE
    all_lines = []
    $game_temp.vms[:chat_log].each do |name, text|
      all_lines.concat(VMS.wrap_chat_line(tmp, "#{name}: #{text}", text_width))
    end
    tmp.dispose

    lines = all_lines.last(VMS::CHAT_VISIBLE_LINES)
    return if lines.empty?

    height = lines.length * CHAT_LINE_HEIGHT + CHAT_PAD * 2
    bmp = Bitmap.new(width, height)
    if outline > 0
      VMS.draw_rounded_rect(bmp, 0, 0, width, height, VMS::CHAT_BOX_RADIUS, VMS::CHAT_BOX_OUTLINE_COLOR)
      VMS.draw_rounded_rect(bmp, outline, outline, width - outline * 2, height - outline * 2,
                             [VMS::CHAT_BOX_RADIUS - outline, 0].max, Color.new(0, 0, 0, VMS::CHAT_BOX_OPACITY))
    else
      VMS.draw_rounded_rect(bmp, 0, 0, width, height, VMS::CHAT_BOX_RADIUS, Color.new(0, 0, 0, VMS::CHAT_BOX_OPACITY))
    end
    bmp.font.size = CHAT_FONT_SIZE
    lines.each_with_index do |text, i|
      y = CHAT_PAD + i * CHAT_LINE_HEIGHT
      bmp.font.color = Color.new(0, 0, 0, 255)
      [[-1,0],[1,0],[0,-1],[0,1]].each { |ox, oy| bmp.draw_text(CHAT_PAD + ox, y + oy, text_width, CHAT_LINE_HEIGHT, text) }
      bmp.font.color = Color.new(255, 255, 255, 255)
      bmp.draw_text(CHAT_PAD, y, text_width, CHAT_LINE_HEIGHT, text)
    end

    @chat_overlay_sprite        = Sprite.new
    @chat_overlay_sprite.bitmap = bmp
    @chat_overlay_sprite.x      = 8
    @chat_overlay_sprite.y      = Graphics.height - height - 8
    @chat_overlay_sprite.z      = 99998
  end

  def self.dispose_chat_overlay
    @chat_overlay_sprite&.dispose
    @chat_overlay_sprite = nil
  end

  def self.check_chat_input
    return unless VMS::ENABLE_CHAT && VMS.is_connected? && $scene.is_a?(Scene_Map)
    return if $game_temp.vms[:chat_input_open]
    return unless Input.trigger?(VMS::CHAT_OPEN_KEY)
    $game_temp.vms[:chat_input_open] = true
    begin
      text = pbEnterBoxName(VMS::CHAT_INPUT_PROMPT, 0, VMS::CHAT_MAX_MESSAGE_LENGTH, "")
      VMS.send_chat_message(text) if text && text != ""
    ensure
      $game_temp.vms[:chat_input_open] = false
    end
  end
end

MenuHandlers.add(:pause_menu, :vms_chat_toggle, {
  "name"      => VMS::CHAT_TOGGLE_MENU_NAME,
  "order"     => 49,
  "condition" => proc {
    VMS::ENABLE_CHAT &&
    VMS::ACCESSIBLE_PROC.call &&
    VMS::ACCESSIBLE_FROM_PAUSE_MENU &&
    VMS.is_connected?
  },
  "effect" => proc { |menu|
    $game_temp.vms[:chat_hidden] = !$game_temp.vms[:chat_hidden]
    $game_temp.vms[:chat_dirty]  = true
    menu.pbEndScene
    next true
  }
})
