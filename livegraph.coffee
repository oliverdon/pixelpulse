
OFFSET = 35

window.arange = (lo, hi, step) ->
	lo -= step
	while lo < hi
		lo += step


class LiveGraph
	constructor: (@div) ->
		@axisCanvas = document.createElement('canvas')
		@graphCanvas = document.createElement('canvas')
		
		@div.appendChild(@axisCanvas)
		@div.appendChild(@graphCanvas)
		
		@axes =
			yleft: {direction:'y', xpos:0}
			yright: {direction:'y', xpos:1}
			xbottom: {direction:'x'}
			
		for name, axis of @axes
			axis.labelDiv = document.createElement('div')
			axis.labelSpan = document.createElement('span')
			axis.labelDiv.setAttribute('class', "livegraph-label livegraph-label-#{name}")
			@div.appendChild(axis.labelDiv)
			axis.labelDiv.appendChild(axis.labelSpan)
		@data = []
		@resized()
				
	resized: () ->
		@width = @div.offsetWidth
		@height = @div.offsetHeight
		@redrawAxis()
		@redrawGraph()
		
	transformForAxis: (ctx, xaxis, yaxis) ->
		ctx.setTransform(1,0,0,1,0,0)
		ctx.translate(OFFSET-0.5, @height-OFFSET-0.5)
		
		xscale = if xaxis then (@width-2*OFFSET)/(xaxis.max-xaxis.min) else 1
		yscale = if yaxis then (@height-2*OFFSET)/(yaxis.max-yaxis.min) else 1
		
		ctx.scale(xscale, -yscale)
		return [xscale, yscale]
	
	transformPoint: (axis, point) -> 
		if axis.direction == 'y'
			@height - OFFSET - point * (@height - OFFSET*2)/(axis.max - axis.min)
		else
			OFFSET + point * (@width - OFFSET*2)/(axis.max - axis.min)
		
	redrawAxis: () ->
		@axisCanvas.width = 1
		@axisCanvas.width = @width
		@axisCanvas.height = @height
		@ctxa = @axisCanvas.getContext('2d')
		
		@ctxa.lineWidth = 2
		
		@ctxa.textBaseline
		
		for name, axis of @axes
			grid=Math.pow(10, Math.round(Math.log(axis.max-axis.min)/Math.LN10)-1)
			if (axis.max-axis.min)/grid >= 10
				grid *= 2
			
			if axis.direction=='y'
				if axis.xpos==0
					x = OFFSET
					@ctxa.textAlign = 'right'
					textoffset = -5
				else 
					x = @width-OFFSET
					@ctxa.textAlign = 'left'
					textoffset = 5
				@ctxa.textBaseline = 'middle'
				
				console.log('x', x, axis.xpos)
				@ctxa.beginPath()
				@ctxa.moveTo(x, OFFSET)
				@ctxa.lineTo(x, @height-OFFSET)
				@ctxa.stroke()
				
				for y in arange(axis.min, axis.max, grid)
					@ctxa.beginPath()
					@ctxa.moveTo(x-4, @transformPoint(axis,y))
					@ctxa.lineTo(x+4, @transformPoint(axis,y))
					@ctxa.stroke()
					@ctxa.fillText(y, x+textoffset, @transformPoint(axis,y))
			else
				y = @height-OFFSET
				@ctxa.beginPath()
				@ctxa.moveTo(OFFSET, y)
				@ctxa.lineTo(@width-OFFSET, y)
				@ctxa.stroke()
				
				textoffset = 5
				@ctxa.textAlign = 'center'
				@ctxa.textBaseline = 'top'
				
				for x in arange(axis.min, axis.max, grid)
					@ctxa.beginPath()
					@ctxa.moveTo(@transformPoint(axis,x),y-4)
					@ctxa.lineTo(@transformPoint(axis,x),y+4)
					@ctxa.stroke()
					@ctxa.fillText(x, @transformPoint(axis,x),y+textoffset)
				
			
	redrawGraph: ()->
		@graphCanvas.width = 1
		@graphCanvas.width = @width
		@graphCanvas.height = @height
		
		@ctxg = @graphCanvas.getContext('2d')
		@ctxg.lineWidth = 2
		
		xaxis = @axes.xbottom
		for yaxis in [@axes.yleft, @axes.yright]		
			@ctxg.beginPath()
			for i in @data
				@ctxg.lineTo(@transformPoint(xaxis,i[xaxis.property]), @transformPoint(yaxis,i[yaxis.property]))
			@ctxg.stroke()
		
	
	pushData: (pt) ->
		@data.push(pt)
		@redrawGraph()
	
	setData: (@data) ->
		@redrawGraph()
	
	setAxis: (axis, label, property, min, max) ->
		axis.property = property
		axis.min = min
		axis.max = max
		axis.labelSpan.innerText = label
		@redrawAxis()
		
window.LiveGraph = LiveGraph
	
